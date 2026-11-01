// AEAD engines for the Wraith secure channel.
//
// Every frame is sealed with ChaCha20-Poly1305 under a per-direction key and
// a 96-bit nonce built from a 64-bit frame counter. The engine only decides
// *where* that computation runs:
//
//  * [CipherAead]   — in the calling isolate, through package:cryptography.
//                     With cryptography_flutter enabled this is the OS's
//                     native implementation (Android, iOS, macOS).
//  * [FastAead]     — the optimised pure-Dart RFC 8439 implementation in
//                     chacha_poly.dart, in the calling isolate.
//  * [IsolateAead]  — a pool of worker isolates running [FastAead], so large
//                     frames are processed on several CPU cores in parallel.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'chacha_poly.dart';
import 'models.dart';

const int kTagLength = 16;

/// 12-byte nonce: 4 zero bytes ‖ 64-bit big-endian counter.
Uint8List wraithNonce(int counter) {
  final b = ByteData(12)
    ..setUint32(4, (counter >> 32) & 0xFFFFFFFF)
    ..setUint32(8, counter & 0xFFFFFFFF);
  return b.buffer.asUint8List();
}

abstract class AeadEngine {
  /// Returns `ciphertext ‖ tag`.
  Future<Uint8List> seal(Uint8List key, int counter, Uint8List plaintext);

  /// Takes `ciphertext ‖ tag`; throws [WraithException] if authentication fails.
  Future<Uint8List> open(Uint8List key, int counter, Uint8List sealed);

  /// Engine used by new channels. Apps may replace it at startup
  /// (e.g. with a native-backed [CipherAead]).
  static AeadEngine? _instance;
  static AeadEngine get instance => _instance ??= IsolateAead();
  static set instance(AeadEngine engine) => _instance = engine;
}

const _tampered = WraithException('Integrity check failed — traffic was tampered with');

/// Optimised pure-Dart ChaCha20-Poly1305 in the current isolate.
class FastAead implements AeadEngine {
  const FastAead();

  @override
  Future<Uint8List> seal(Uint8List key, int counter, Uint8List plaintext) async =>
      ChaCha20Poly1305.seal(key, wraithNonce(counter), plaintext);

  @override
  Future<Uint8List> open(Uint8List key, int counter, Uint8List sealed) async =>
      ChaCha20Poly1305.open(key, wraithNonce(counter), sealed) ?? (throw _tampered);
}

/// Seals in the current isolate with any package:cryptography cipher.
class CipherAead implements AeadEngine {
  CipherAead([Cipher? cipher]) : _cipher = cipher ?? Chacha20.poly1305Aead();
  final Cipher _cipher;

  @override
  Future<Uint8List> seal(Uint8List key, int counter, Uint8List plaintext) async {
    final box = await _cipher.encrypt(plaintext, secretKey: SecretKey(key), nonce: wraithNonce(counter));
    final ct = box.cipherText;
    final out = Uint8List(ct.length + kTagLength)
      ..setRange(0, ct.length, ct)
      ..setRange(ct.length, ct.length + kTagLength, box.mac.bytes);
    return out;
  }

  @override
  Future<Uint8List> open(Uint8List key, int counter, Uint8List sealed) async {
    if (sealed.length < kTagLength) throw _tampered;
    final split = sealed.length - kTagLength;
    try {
      final plain = await _cipher.decrypt(
        SecretBox(
          Uint8List.sublistView(sealed, 0, split),
          nonce: wraithNonce(counter),
          mac: Mac(Uint8List.sublistView(sealed, split)),
        ),
        secretKey: SecretKey(key),
      );
      return plain is Uint8List ? plain : Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw _tampered;
    }
  }
}

/// Spreads sealing/opening of large frames over a pool of worker isolates.
/// Small frames are handled inline (message passing would cost more).
class IsolateAead implements AeadEngine {
  // Leave two cores for the UI and raster threads (and the hash isolate), so
  // a busy transfer never makes the interface stutter.
  IsolateAead({int? workers}) : _size = workers ?? max(1, min(4, Platform.numberOfProcessors - 2));

  static const int inlineThreshold = 16 * 1024;

  final int _size;
  final FastAead _inline = const FastAead();
  final List<_Worker> _workers = [];
  Future<void>? _starting;
  int _next = 0;

  int get workers => _size;

  Future<void> _ensureStarted() => _starting ??= () async {
        for (var i = 0; i < _size; i++) {
          _workers.add(await _Worker.spawn());
        }
      }();

  Future<Uint8List> _run(bool seal, Uint8List key, int counter, Uint8List data) async {
    await _ensureStarted();
    final worker = _workers[_next++ % _workers.length];
    final out = await worker.call(seal, key, counter, data);
    if (out == null) throw _tampered;
    return out;
  }

  @override
  Future<Uint8List> seal(Uint8List key, int counter, Uint8List plaintext) =>
      plaintext.length < inlineThreshold ? _inline.seal(key, counter, plaintext) : _run(true, key, counter, plaintext);

  @override
  Future<Uint8List> open(Uint8List key, int counter, Uint8List sealed) =>
      sealed.length < inlineThreshold ? _inline.open(key, counter, sealed) : _run(false, key, counter, sealed);

  void dispose() {
    for (final w in _workers) {
      w.kill();
    }
    _workers.clear();
    _starting = null;
  }
}

class _Worker {
  _Worker._(this._inbox);

  final ReceivePort _inbox;
  late final SendPort _outbox;
  late final Isolate _isolate;
  final Map<int, Completer<Uint8List?>> _pending = {};
  int _ids = 0;

  static Future<_Worker> spawn() async {
    final inbox = ReceivePort();
    final worker = _Worker._(inbox);
    final ready = Completer<SendPort>();
    inbox.listen((dynamic msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        return;
      }
      final list = msg as List<dynamic>;
      if (list.isNotEmpty && list[0] is int) {
        final completer = worker._pending.remove(list[0] as int);
        final payload = list[1];
        completer?.complete(payload == null ? null : (payload as TransferableTypedData).materialize().asUint8List());
      } else {
        // Uncaught error inside the worker: fail everything in flight.
        final error = WraithException('Crypto worker crashed: ${list.isEmpty ? '?' : list[0]}');
        for (final c in worker._pending.values) {
          c.completeError(error);
        }
        worker._pending.clear();
      }
    });
    worker._isolate = await Isolate.spawn(_aeadWorkerMain, inbox.sendPort,
        onError: inbox.sendPort, debugName: 'wraith-aead');
    worker._outbox = await ready.future;
    return worker;
  }

  Future<Uint8List?> call(bool seal, Uint8List key, int counter, Uint8List data) {
    final id = _ids++;
    final completer = Completer<Uint8List?>();
    _pending[id] = completer;
    _outbox.send([id, seal, key, counter, TransferableTypedData.fromList([data])]);
    return completer.future;
  }

  void kill() {
    _isolate.kill(priority: Isolate.immediate);
    _inbox.close();
  }
}

@pragma('vm:entry-point')
void _aeadWorkerMain(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  const cipher = FastAead();
  inbox.listen((dynamic msg) async {
    final m = msg as List<dynamic>;
    final id = m[0] as int;
    final seal = m[1] as bool;
    final key = m[2] as Uint8List;
    final counter = m[3] as int;
    final data = (m[4] as TransferableTypedData).materialize().asUint8List();
    try {
      final result = seal ? await cipher.seal(key, counter, data) : await cipher.open(key, counter, data);
      out.send([id, TransferableTypedData.fromList([result])]);
    } catch (_) {
      out.send([id, null]);
    }
  });
}
