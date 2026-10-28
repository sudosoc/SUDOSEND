import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
}

class FileEntry {
  const FileEntry({required this.name, required this.size, this.path});
  final String name;
  final int size;
  final String? path;
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

class TransferJob extends ChangeNotifier {
  TransferJob({
    required this.direction,
    required this.peerName,
    required this.files,
    required this.status,
    this.peerPlatform = 'unknown',
  })  : id = DateTime.now().microsecondsSinceEpoch.toString(),
        totalBytes = files.fold<int>(0, (a, f) => a + f.size),
        startedAt = DateTime.now();

  final String id;
  final TransferDirection direction;
  final List<FileEntry> files;
  final int totalBytes;
  final DateTime startedAt;

  String peerName;
  String peerPlatform;
  String? peerFingerprint;
  bool peerTrusted = false;
  String? sas;
  TransferStatus status;
  int doneBytes = 0;
  double speed = 0;
  String? error;
  int verifiedFiles = 0;
  final List<String> savedPaths = [];
  bool cancelRequested = false;
  DateTime? finishedAt;
  int _lastNotifyMs = -1000;

  double get progress => totalBytes == 0
      ? (status == TransferStatus.done ? 1 : 0)
      : (doneBytes / totalBytes).clamp(0.0, 1.0);

  bool get isActive =>
      status == TransferStatus.connecting ||
      status == TransferStatus.awaitingApproval ||
      status == TransferStatus.transferring ||
      status == TransferStatus.verifying;

  void update(void Function() fn) {
    fn();
    notifyListeners();
  }

  void addProgress(int bytes, Stopwatch clock) {
    doneBytes += bytes;
    final now = clock.elapsedMilliseconds;
    if (now - _lastNotifyMs >= 100 || doneBytes >= totalBytes) {
      speed = now > 0 ? doneBytes / (now / 1000) : 0;
      _lastNotifyMs = now;
      notifyListeners();
    }
  }

  void cancel() {
    if (!isActive) return;
    cancelRequested = true;
    notifyListeners();
  }

  void finish(TransferStatus s) {
    status = s;
    finishedAt = DateTime.now();
    notifyListeners();
  }

  void fail(Object e) {
    if (cancelRequested) {
      status = TransferStatus.cancelled;
    } else {
      status = TransferStatus.failed;
      error = describeError(e);
    }
    finishedAt = DateTime.now();
    notifyListeners();
  }
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
