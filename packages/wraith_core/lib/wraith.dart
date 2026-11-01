// Wraith Protocol v1 — the wire protocol behind SUDOSEND.
// See PROTOCOL.md for the full specification.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'aead.dart';
import 'identity.dart';
import 'models.dart';
import 'util.dart';

const String kProtocol = 'WRAITH/1';
const int kDiscoveryPort = 47823;
const int kTransferPort = 47824;
const int kChunkSize = 256 * 1024;
const int kMaxFrame = 1024 * 1024;
const int _kMaxHello = 4096;

/// Encrypted frame types (first byte of the decrypted payload).
class Frame {
  Frame._();
  static const int auth = 1;
  static const int offer = 2;
  static const int accept = 3;
  static const int decline = 4;
  static const int fileStart = 5;
  static const int data = 6;
  static const int fileEnd = 7;
  static const int done = 8;
  static const int result = 9;
  static const int cancel = 10;
  static const int error = 11;
}

// ───────────────────────────── Framing ─────────────────────────────

/// Writes `u32 big-endian length || payload`.
void writeFrame(IOSink sink, List<int> payload) {
  if (payload.length > kMaxFrame + 64) {
    throw const WraithException('Frame too large');
  }
  final header = ByteData(4)..setUint32(0, payload.length);
  sink.add(header.buffer.asUint8List());
  sink.add(payload);
}

/// Buffered reader that turns a socket byte stream into length-prefixed
/// frames, with backpressure (pauses the socket when the buffer is large).
class FrameReader {
  FrameReader(Stream<Uint8List> stream) {
    _sub = stream.listen(
      (chunk) {
        _chunks.add(chunk);
        _available += chunk.length;
        if (_available > _highWater && !_sub.isPaused) _sub.pause();
        _wake();
      },
      onError: (Object e) {
        _error = e;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  static const int _highWater = 16 * 1024 * 1024;
  static const int _lowWater = 4 * 1024 * 1024;

  late final StreamSubscription<Uint8List> _sub;
  final ListQueue<Uint8List> _chunks = ListQueue<Uint8List>();
  int _available = 0;
  int _headOffset = 0;
  Completer<void>? _waiter;
  bool _closed = false;
  Object? _error;

  void _wake() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<Uint8List> _readExactly(int n) async {
    while (_available < n) {
      final err = _error;
      if (err != null) throw err;
      if (_closed) throw const WraithException('Connection closed by the other device');
      if (_sub.isPaused) _sub.resume();
      final w = Completer<void>();
      _waiter = w;
      await w.future;
    }
    final out = Uint8List(n);
    var written = 0;
    while (written < n) {
      final head = _chunks.first;
      final take = min(n - written, head.length - _headOffset);
      out.setRange(written, written + take, head, _headOffset);
      written += take;
      _headOffset += take;
      if (_headOffset == head.length) {
        _chunks.removeFirst();
        _headOffset = 0;
      }
    }
    _available -= n;
    if (_sub.isPaused && _available < _lowWater) _sub.resume();
    return out;
  }

  Future<Uint8List> readFrame({int maxLen = kMaxFrame + 64}) async {
    final header = await _readExactly(4);
    final len = ByteData.sublistView(header).getUint32(0);
    if (len > maxLen) throw const WraithException('Oversized frame rejected');
    return _readExactly(len);
  }

  Future<void> cancel() => _sub.cancel();
}

// ─────────────────────────── Secure channel ───────────────────────────

class WraithMessage {
  const WraithMessage(this.type, this.body);
  final int type;
  final Uint8List body;

  Map<String, dynamic> json() {
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is! Map<String, dynamic>) {
      throw const WraithException('Malformed message');
    }
    return decoded;
  }
}

/// ChaCha20-Poly1305 channel with one key per direction and an implicit
/// 64-bit frame counter as nonce: reordered, replayed, or modified frames
/// fail authentication.
///
/// Throughput: frames are sealed/opened concurrently by the [AeadEngine]
/// (worker isolates or native code) while the socket keeps moving bytes.
/// Order is preserved by a write chain on the sending side and a prefetch
/// queue on the receiving side; nonces are assigned at call time.
class SecureChannel {
  SecureChannel._(this._socket, this._reader, this._txKey, this._rxKey, this._aead);

  final Socket _socket;
  final FrameReader _reader;
  final Uint8List _txKey;
  final Uint8List _rxKey;
  final AeadEngine _aead;
  int _txCounter = 0;
  int _rxCounter = 0;
  bool _closed = false;

  // Sending: sequential write chain + bounded number of frames in flight.
  Future<void> _tail = Future<void>.value();
  final Queue<Future<void>> _inflight = Queue<Future<void>>();
  int _unflushed = 0;
  static const int _maxInflight = 8;
  static const int _flushEvery = 1024 * 1024;

  // Receiving: frames are read and opened ahead of the consumer.
  final Queue<Future<WraithMessage>> _prefetch = Queue<Future<WraithMessage>>();
  Future<Uint8List>? _lastRead;
  static const int _prefetchDepth = 6;

  /// Sends one frame. With [flush] (default) the call completes once the
  /// frame is handed to the OS. Without it the frame is queued and the call
  /// only waits when too many frames are in flight (bulk data).
  Future<void> send(int type, [List<int> body = const [], bool flush = true]) async {
    if (_closed) throw const WraithException('Connection closed');
    final plain = Uint8List(body.length + 1);
    plain[0] = type;
    plain.setRange(1, plain.length, body);
    final sealed = _aead.seal(_txKey, _txCounter++, plain);
    sealed.ignore();
    final written = _tail.then((_) async {
      final frame = await sealed;
      writeFrame(_socket, frame);
      _unflushed += frame.length + 4;
      if (flush || _unflushed >= _flushEvery) {
        _unflushed = 0;
        await _socket.flush();
      }
    });
    written.ignore();
    _tail = written;
    if (flush) {
      _inflight.clear();
      await written;
      return;
    }
    _inflight.add(written);
    while (_inflight.length > _maxInflight) {
      await _inflight.removeFirst();
    }
  }

  Future<void> sendJson(int type, Map<String, Object?> message) =>
      send(type, utf8.encode(jsonEncode(message)));

  /// Waits until every queued frame has been written and flushed.
  Future<void> drain() async {
    final done = _tail.then((_) => _socket.flush());
    _tail = done;
    _inflight.clear();
    await done;
  }

  Future<WraithMessage> _readNext() {
    final counter = _rxCounter++;
    final previous = _lastRead;
    final raw = previous == null ? _reader.readFrame() : previous.then((_) => _reader.readFrame());
    raw.ignore();
    _lastRead = raw;
    final message = raw.then((frame) async {
      if (frame.length < kTagLength + 1) throw const WraithException('Malformed frame');
      final plain = await _aead.open(_rxKey, counter, frame);
      if (plain.isEmpty) throw const WraithException('Empty frame');
      return WraithMessage(plain[0], Uint8List.sublistView(plain, 1));
    });
    message.ignore();
    return message;
  }

  Future<WraithMessage> receive({Duration? timeout}) {
    while (_prefetch.length < _prefetchDepth) {
      _prefetch.add(_readNext());
    }
    final next = _prefetch.removeFirst();
    return timeout == null ? next : next.timeout(timeout);
  }

  /// Receives a frame and insists on [type]; peer errors/cancels become exceptions.
  Future<WraithMessage> expect(int type, {Duration? timeout}) async {
    final m = await receive(timeout: timeout);
    if (m.type == Frame.error) {
      throw WraithException('Other device reported: ${utf8.decode(m.body, allowMalformed: true)}');
    }
    if (m.type == Frame.cancel) throw const WraithException('Cancelled by the other device');
    if (m.type != type) throw WraithException('Protocol violation (unexpected frame ${m.type})');
    return m;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _tail.timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await _reader.cancel();
    } catch (_) {}
    try {
      await _socket.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _socket.destroy();
  }
}

// ───────────────────────────── Handshake ─────────────────────────────

class Handshake {
  const Handshake({
    required this.channel,
    required this.peerFingerprint,
    required this.peerName,
    required this.peerPlatform,
    required this.sas,
    required this.peerIdentityKey,
    required this.transcript,
  });

  final SecureChannel channel;

  /// The peer's long-term Ed25519 public key (proven by its AUTH signature).
  final List<int> peerIdentityKey;

  /// SHA-256 transcript hash — unique per session; receipts are bound to it.
  final List<int> transcript;
  final String peerFingerprint;
  final String peerName;
  final String peerPlatform;

  /// 6-digit Short Authentication String. Equal on both screens ⇔ no MITM.
  final String sas;
}

class _Hello {
  _Hello(this.ephemeral, this.identity, this.name, this.platform);
  final List<int> ephemeral;
  final List<int> identity;
  final String name;
  final String platform;
}

_Hello _parseHello(Uint8List raw) {
  final m = jsonDecode(utf8.decode(raw));
  if (m is! Map<String, dynamic> || m['proto'] != kProtocol) {
    throw const WraithException('Not a Wraith/1 peer');
  }
  final eph = base64Decode(m['eph'] as String);
  final id = base64Decode(m['id'] as String);
  if (eph.length != 32 || id.length != 32) throw const WraithException('Bad key length');
  final name = m['name'];
  final platform = m['platform'];
  return _Hello(
    eph,
    id,
    sanitizeDeviceName(name is String ? name : 'Unknown device'),
    platform is String && platform.length < 16 ? platform : 'unknown',
  );
}

List<int> _u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();

List<int> _authMessage(String role, List<int> transcript) =>
    [...utf8.encode('$kProtocol auth $role'), ...transcript];

/// Runs the Wraith/1 handshake. The initiator is the sender.
///
/// 1. C → S  COMMIT  = SHA-256(HelloC)         (hash commitment)
/// 2. S → C  HelloS                            (S's keys, before seeing C's)
/// 3. C → S  HelloC                            (S checks it matches COMMIT)
/// 4. Both:  TH = SHA-256(label ‖ HelloC ‖ HelloS)
///           K  = HKDF(X25519(eC, eS), salt = TH)  → k_c2s, k_s2c, sas
/// 5. Both → AUTH = Ed25519(identity, role ‖ TH)   (encrypted)
///
/// The commitment stops a man-in-the-middle from grinding ephemeral keys
/// until both sides show the same SAS.
Future<Handshake> wraithHandshake({
  required Socket socket,
  required FrameReader reader,
  required DeviceIdentity me,
  required bool initiator,
  AeadEngine? aead,
}) async {
  const step = Duration(seconds: 15);
  try {
    final x25519 = X25519();
    final ephemeral = await x25519.newKeyPair();
    final ephemeralPub = (await ephemeral.extractPublicKey()).bytes;
    final myHello = Uint8List.fromList(utf8.encode(jsonEncode({
      'proto': kProtocol,
      'eph': base64Encode(ephemeralPub),
      'id': base64Encode(me.publicKey),
      'name': me.name,
      'platform': platformName(),
    })));

    final Uint8List helloC;
    final Uint8List helloS;
    if (initiator) {
      final commit = crypto.sha256.convert(myHello).bytes;
      writeFrame(socket, utf8.encode(jsonEncode({'proto': kProtocol, 'commit': base64Encode(commit)})));
      await socket.flush();
      helloS = await reader.readFrame(maxLen: _kMaxHello).timeout(step);
      writeFrame(socket, myHello);
      await socket.flush();
      helloC = myHello;
    } else {
      final commitRaw = await reader.readFrame(maxLen: _kMaxHello).timeout(step);
      final commitMsg = jsonDecode(utf8.decode(commitRaw));
      if (commitMsg is! Map<String, dynamic> || commitMsg['proto'] != kProtocol) {
        throw const WraithException('Not a Wraith/1 peer');
      }
      final commit = base64Decode(commitMsg['commit'] as String);
      writeFrame(socket, myHello);
      await socket.flush();
      helloS = myHello;
      helloC = await reader.readFrame(maxLen: _kMaxHello).timeout(step);
      if (!constantTimeEquals(crypto.sha256.convert(helloC).bytes, commit)) {
        throw const WraithException('Commitment mismatch — possible man-in-the-middle');
      }
    }

    final peer = _parseHello(initiator ? helloS : helloC);
    if (constantTimeEquals(peer.identity, me.publicKey)) {
      throw const WraithException('Refusing to connect to myself');
    }

    final transcript = crypto.sha256.convert([
      ...utf8.encode('$kProtocol transcript'),
      ..._u32(helloC.length), ...helloC,
      ..._u32(helloS.length), ...helloS,
    ]).bytes;

    final shared = await x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(peer.ephemeral, type: KeyPairType.x25519),
    );
    final sharedBytes = await shared.extractBytes();
    if (sharedBytes.every((b) => b == 0)) {
      throw const WraithException('Invalid key exchange (low-order point)');
    }

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    Future<SecretKey> derive(String label) =>
        hkdf.deriveKey(secretKey: shared, nonce: transcript, info: utf8.encode('$kProtocol $label'));
    final c2s = Uint8List.fromList(await (await derive('c2s')).extractBytes());
    final s2c = Uint8List.fromList(await (await derive('s2c')).extractBytes());
    final sasBytes = await (await derive('sas')).extractBytes();
    final sasValue =
        ((sasBytes[0] << 24) | (sasBytes[1] << 16) | (sasBytes[2] << 8) | sasBytes[3]) % 1000000;
    final sas = sasValue.toString().padLeft(6, '0');

    final channel = SecureChannel._(
        socket, reader, initiator ? c2s : s2c, initiator ? s2c : c2s, aead ?? AeadEngine.instance);

    final ed25519 = Ed25519();
    final signature = await ed25519.sign(
      _authMessage(initiator ? 'C' : 'S', transcript),
      keyPair: me.keyPair,
    );
    await channel.send(Frame.auth, signature.bytes);
    final auth = await channel.expect(Frame.auth, timeout: step);
    final valid = await ed25519.verify(
      _authMessage(initiator ? 'S' : 'C', transcript),
      signature: Signature(
        auth.body,
        publicKey: SimplePublicKey(peer.identity, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) throw const WraithException('Identity signature invalid — connection rejected');

    return Handshake(
      channel: channel,
      peerFingerprint: fingerprintOf(peer.identity),
      peerName: peer.name,
      peerPlatform: peer.platform,
      sas: sas,
      peerIdentityKey: peer.identity,
      transcript: transcript,
    );
  } on WraithException {
    rethrow;
  } on SocketException {
    rethrow;
  } on TimeoutException {
    rethrow;
  } catch (_) {
    throw const WraithException('Handshake failed: malformed data from peer');
  }
}

// ─────────────────────────── Streaming SHA-256 ───────────────────────────

class Sha256Stream {
  Sha256Stream() {
    _input = crypto.sha256.startChunkedConversion(_output);
  }

  final _DigestSink _output = _DigestSink();
  late final ByteConversionSink _input;

  void add(List<int> data) => _input.add(data);

  List<int> close() {
    _input.close();
    return _output.value!.bytes;
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}
