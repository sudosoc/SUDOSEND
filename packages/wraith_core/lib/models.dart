// Pure Dart (no Flutter imports) so the same core powers the app and the CLI.
import 'dart:async';
import 'dart:io';

import 'receipt.dart';

class WraithException implements Exception {
  const WraithException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A device discovered on the LAN (or added manually by IP).
class Peer {
  Peer({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.lastSeen,
    this.manual = false,
    this.alternates = const [],
  });

  factory Peer.manual(InternetAddress address, int port) => Peer(
        id: 'manual:${address.address}',
        name: address.address,
        platform: 'unknown',
        address: address,
        port: port,
        lastSeen: DateTime.now(),
        manual: true,
      );

  /// Fingerprint of the device identity key (32 hex chars).
  final String id;
  final String name;
  final String platform;
  final InternetAddress address;
  final int port;
  final DateTime lastSeen;
  final bool manual;

  /// Other addresses to try if [address] does not answer (QR pairing).
  final List<InternetAddress> alternates;
}

/// A file to send or being received. [name] is a relative path using '/'
/// separators ("photo.jpg" or "Project/src/main.c" for folder transfers).
class FileEntry {
  const FileEntry({required this.name, required this.size, this.path, this.mtime});
  final String name;
  final int size;
  final String? path;

  /// Modification time (ms since epoch) — preserved by folder sync.
  final int? mtime;
}

enum TransferDirection { outgoing, incoming }

enum TransferStatus {
  connecting,
  awaitingApproval,
  transferring,
  verifying,
  done,
  declined,
  failed,
  cancelled,
}

class TransferJob {
  TransferJob({
    required this.direction,
    required this.peerName,
    required this.files,
    required this.status,
    this.peerPlatform = 'unknown',
    this.text,
  })  : id = '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
        totalBytes = files.fold<int>(0, (a, f) => a + f.size),
        startedAt = DateTime.now();

  static int _seq = 0;

  /// Minimum time between progress notifications (UI refresh rate).
  static int progressIntervalMs = 150;

  /// A clipboard-sync push (handled silently by the apps).
  bool clipboard = false;

  /// A "find my device" ring request (no files).
  bool ring = false;

  /// A chat message (text, handled by the Messages screen).
  bool chat = false;

  /// Folder-sync transfer: the sync pair id.
  String? syncId;

  /// Bytes that travelled compressed (smart compression), for stats.
  int compressedSaved = 0;

  final String id;
  final TransferDirection direction;
  final List<FileEntry> files;
  final int totalBytes;
  final DateTime startedAt;

  /// Set for text/clipboard transfers (then [files] is empty).
  final String? text;

  String peerName;
  String peerPlatform;
  String? peerFingerprint;

  /// IP of the other side (and its Wraith port, outgoing only) — lets the
  /// app reach a device again even when its discovery beacons are not seen.
  String? peerAddress;
  int? peerPort;
  bool peerTrusted = false;
  String? sas;
  TransferStatus status;
  int doneBytes = 0;

  /// Bytes skipped because they were already on the receiver (resume).
  int resumedBytes = 0;
  double speed = 0;
  String? error;
  int verifiedFiles = 0;
  final List<String> savedPaths = [];

  /// SHA-256 (hex) of every saved file, by path — verified on arrival.
  final Map<String, String> savedHashes = {};

  /// Fastest rate seen over a short window, bytes/s.
  double peakSpeed = 0;

  /// Time spent actually moving data (excludes waiting for approval).
  int transferMs = 0;

  /// Signed proof of delivery (set when the transfer completes).
  DeliveryReceipt? receipt;
  bool cancelRequested = false;
  DateTime? finishedAt;
  int _lastNotifyMs = -1000;
  int _windowMs = 0;
  int _windowBytes = 0;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Emits whenever the job's state changes (progress is throttled to ~10 Hz).
  Stream<void> get changes => _changes.stream;

  bool get isText => text != null;

  double get progress => totalBytes == 0
      ? (status == TransferStatus.done ? 1 : 0)
      : (doneBytes / totalBytes).clamp(0.0, 1.0);

  bool get isActive =>
      status == TransferStatus.connecting ||
      status == TransferStatus.awaitingApproval ||
      status == TransferStatus.transferring ||
      status == TransferStatus.verifying;

  void notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void update(void Function() fn) {
    fn();
    notify();
  }

  void addProgress(int bytes, Stopwatch clock) {
    doneBytes += bytes;
    final now = clock.elapsedMilliseconds;
    transferMs = now;
    // Peak speed over windows of at least 300 ms (shorter ones are noise).
    if (now - _windowMs >= 300) {
      final inst = (doneBytes - _windowBytes) / ((now - _windowMs) / 1000);
      if (_windowMs > 0 && inst > peakSpeed) peakSpeed = inst;
      _windowMs = now;
      _windowBytes = doneBytes;
    }
    if (now - _lastNotifyMs >= progressIntervalMs || doneBytes >= totalBytes) {
      final fresh = doneBytes - resumedBytes;
      speed = now > 0 ? fresh / (now / 1000) : 0;
      _lastNotifyMs = now;
      notify();
    }
  }

  void cancel() {
    if (!isActive) return;
    cancelRequested = true;
    notify();
  }

  void finish(TransferStatus s) {
    status = s;
    finishedAt = DateTime.now();
    notify();
  }

  void fail(Object e) {
    if (cancelRequested) {
      status = TransferStatus.cancelled;
    } else {
      status = TransferStatus.failed;
      error = describeError(e);
    }
    finishedAt = DateTime.now();
    notify();
  }

  void dispose() => _changes.close();
}

String describeError(Object e) {
  if (e is WraithException) return e.message;
  if (e is SocketException) {
    final os = e.osError?.message;
    return 'Connection problem: ${os == null || os.isEmpty ? e.message : os}';
  }
  if (e is TimeoutException) return 'Timed out — the other device stopped responding';
  if (e is FileSystemException) return 'File error: ${e.osError?.message ?? e.message}';
  return 'Unexpected error: $e';
}
