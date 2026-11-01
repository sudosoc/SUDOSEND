import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wraith_core/models.dart';

/// A finished transfer, kept across restarts. Text message contents are
/// deliberately not stored (they may be passwords or links).
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.direction,
    required this.peerName,
    required this.peerPlatform,
    required this.fileCount,
    required this.totalBytes,
    required this.status,
    required this.isText,
    required this.at,
    this.error,
    this.firstName,
    this.savedPaths = const [],
    this.receiptPath,
  });

  factory HistoryEntry.fromJob(TransferJob job, {String? receiptPath}) => HistoryEntry(
        id: job.id,
        direction: job.direction,
        peerName: job.peerName,
        peerPlatform: job.peerPlatform,
        fileCount: job.files.length,
        totalBytes: job.totalBytes,
        status: job.status,
        isText: job.isText,
        at: job.finishedAt ?? DateTime.now(),
        error: job.error,
        firstName: job.files.isEmpty ? null : job.files.first.name,
        savedPaths: List.of(job.savedPaths.take(50)),
        receiptPath: receiptPath,
      );

  factory HistoryEntry.fromJson(Map<String, dynamic> m) => HistoryEntry(
        id: m['id'] as String,
        direction: TransferDirection.values.byName(m['dir'] as String),
        peerName: m['peer'] as String,
        peerPlatform: (m['platform'] as String?) ?? 'unknown',
        fileCount: m['files'] as int,
        totalBytes: m['bytes'] as int,
        status: TransferStatus.values.byName(m['status'] as String),
        isText: (m['text'] as bool?) ?? false,
        at: DateTime.parse(m['at'] as String),
        error: m['error'] as String?,
        firstName: m['first'] as String?,
        savedPaths: [for (final s in (m['saved'] as List<dynamic>? ?? const [])) s as String],
        receiptPath: m['receipt'] as String?,
      );

  final String id;
  final TransferDirection direction;
  final String peerName;
  final String peerPlatform;
  final int fileCount;
  final int totalBytes;
  final TransferStatus status;
  final bool isText;
  final DateTime at;
  final String? error;
  final String? firstName;
  final List<String> savedPaths;

  /// Signed delivery receipt stored in the app's data folder.
  final String? receiptPath;

  Map<String, Object?> toJson() => {
        'id': id,
        'dir': direction.name,
        'peer': peerName,
        'platform': peerPlatform,
        'files': fileCount,
        'bytes': totalBytes,
        'status': status.name,
        'text': isText,
        'at': at.toIso8601String(),
        'error': error,
        'first': firstName,
        'saved': savedPaths,
        'receipt': receiptPath,
      };
}

class HistoryStore {
  HistoryStore._(this._file, this.entries);

  static const int limit = 300;
  final File _file;

  /// Newest first.
  final List<HistoryEntry> entries;

  static Future<HistoryStore> load(Directory dir) async {
    final file = File(p.join(dir.path, 'history.json'));
    final entries = <HistoryEntry>[];
    try {
      if (await file.exists()) {
        for (final e in jsonDecode(await file.readAsString()) as List<dynamic>) {
          try {
            entries.add(HistoryEntry.fromJson(e as Map<String, dynamic>));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return HistoryStore._(file, entries);
  }

  Future<void> add(HistoryEntry entry) async {
    entries.removeWhere((e) => e.id == entry.id);
    entries.insert(0, entry);
    if (entries.length > limit) entries.removeRange(limit, entries.length);
    await _save();
  }

  /// Pretty JSON of the whole history (for export / audit).
  String exportJson() => const JsonEncoder.withIndent('  ').convert([for (final e in entries) e.toJson()]);

  Future<void> clear() async {
    entries.clear();
    await _save();
  }

  Future<void> _save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode([for (final e in entries) e.toJson()]));
    } catch (_) {}
  }
}
