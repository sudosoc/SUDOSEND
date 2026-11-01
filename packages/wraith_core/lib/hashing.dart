// SHA-256 of a file as its chunks stream by. Large files are hashed on a
// shared background isolate so hashing overlaps with network and disk I/O
// instead of competing with them on the main isolate.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'wraith.dart' show Sha256Stream;

abstract class ChunkHasher {
  void add(Uint8List chunk);
  Future<List<int>> close();

  /// Files at least this big are hashed off the main isolate.
  static const int backgroundThreshold = 4 * 1024 * 1024;

  static ChunkHasher create(int expectedSize) =>
      expectedSize >= backgroundThreshold ? _BackgroundHasher() : _InlineHasher();
}

class _InlineHasher implements ChunkHasher {
  final Sha256Stream _sha = Sha256Stream();
  @override
  void add(Uint8List chunk) => _sha.add(chunk);
  @override
  Future<List<int>> close() async => _sha.close();
}

class _BackgroundHasher implements ChunkHasher {
  _BackgroundHasher() : _id = _HashService.instance.begin();
  final Future<int> _id;

  @override
  void add(Uint8List chunk) {
    final copy = TransferableTypedData.fromList([chunk]);
    _id.then((id) => _HashService.instance.add(id, copy));
  }

  @override
  Future<List<int>> close() async => _HashService.instance.end(await _id);
}

class _HashService {
  _HashService._();
  static final _HashService instance = _HashService._();

  SendPort? _port;
  Future<void>? _starting;
  int _ids = 0;
  final Map<int, Completer<List<int>>> _pending = {};

  Future<void> _ensure() => _starting ??= () async {
        final inbox = ReceivePort();
        final ready = Completer<SendPort>();
        inbox.listen((dynamic msg) {
          if (msg is SendPort) {
            ready.complete(msg);
          } else if (msg is List && msg.isNotEmpty && msg[0] is int) {
            _pending.remove(msg[0] as int)?.complete((msg[1] as TransferableTypedData).materialize().asUint8List());
          } else {
            final error = StateError('hash worker crashed');
            for (final c in _pending.values) {
              c.completeError(error);
            }
            _pending.clear();
          }
        });
        await Isolate.spawn(_hashWorkerMain, inbox.sendPort, onError: inbox.sendPort, debugName: 'wraith-sha256');
        _port = await ready.future;
      }();

  Future<int> begin() async {
    await _ensure();
    final id = _ids++;
    _port!.send(['begin', id]);
    return id;
  }

  void add(int id, TransferableTypedData data) => _port!.send(['add', id, data]);

  Future<List<int>> end(int id) {
    final completer = Completer<List<int>>();
    _pending[id] = completer;
    _port!.send(['end', id]);
    return completer.future;
  }
}

@pragma('vm:entry-point')
void _hashWorkerMain(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  final sessions = <int, Sha256Stream>{};
  inbox.listen((dynamic msg) {
    final m = msg as List<dynamic>;
    final id = m[1] as int;
    switch (m[0] as String) {
      case 'begin':
        sessions[id] = Sha256Stream();
      case 'add':
        sessions[id]?.add((m[2] as TransferableTypedData).materialize().asUint8List());
      case 'end':
        final digest = sessions.remove(id)?.close() ?? const <int>[];
        out.send([id, TransferableTypedData.fromList([Uint8List.fromList(digest)])]);
    }
  });
}
