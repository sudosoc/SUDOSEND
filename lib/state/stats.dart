import 'dart:convert';

import 'package:wraith_core/models.dart';
import 'package:wraith_core/organize.dart';

import 'history.dart';
import 'library.dart';

/// Activity buckets for the chart.
enum StatsPeriod { daily, weekly, monthly }

class ActivityBucket {
  ActivityBucket(this.start, this.label);
  final DateTime start;
  final String label;
  int sent = 0;
  int received = 0;
  int get total => sent + received;
}

/// Everything the dashboard shows, computed from history and the library.
class Stats {
  Stats(this.history, this.library, {required this.nameOf});

  final List<HistoryEntry> history;
  final List<LibraryItem> library;

  /// Display name for a history entry (nickname when known).
  final String Function(HistoryEntry e) nameOf;

  Iterable<HistoryEntry> get _done => history.where((e) => e.status == TransferStatus.done && !e.isText);

  int get filesReceived => _done.where((e) => e.direction == TransferDirection.incoming).fold(0, (a, e) => a + e.fileCount);
  int get filesSent => _done.where((e) => e.direction == TransferDirection.outgoing).fold(0, (a, e) => a + e.fileCount);
  int get bytesReceived => _done.where((e) => e.direction == TransferDirection.incoming).fold(0, (a, e) => a + e.totalBytes);
  int get bytesSent => _done.where((e) => e.direction == TransferDirection.outgoing).fold(0, (a, e) => a + e.totalBytes);
  int get transfers => history.where((e) => e.status == TransferStatus.done).length;
  int get failed => history.where((e) => e.status == TransferStatus.failed).length;

  /// Bytes-weighted average speed over transfers that reported timing.
  double get averageSpeed {
    var bytes = 0, ms = 0;
    for (final e in _done) {
      if (e.transferMs < 200) continue;
      bytes += e.totalBytes;
      ms += e.transferMs;
    }
    return ms == 0 ? 0 : bytes * 1000 / ms;
  }

  double get peakSpeed => _done.fold(0.0, (a, e) => e.peakSpeed > a ? e.peakSpeed : a);

  /// (device, files, bytes) by who sent you the most, top [n].
  List<(String, int, int)> topSenders([int n = 5]) {
    final m = <String, (int, int)>{};
    for (final e in _done.where((e) => e.direction == TransferDirection.incoming)) {
      final k = nameOf(e);
      final cur = m[k] ?? (0, 0);
      m[k] = (cur.$1 + e.fileCount, cur.$2 + e.totalBytes);
    }
    final l = [for (final e in m.entries) (e.key, e.value.$1, e.value.$2)]..sort((a, b) => b.$2.compareTo(a.$2));
    return l.take(n).toList();
  }

  /// (category, files, bytes) received, most first.
  List<(FileCategory, int, int)> topCategories() {
    final m = <FileCategory, (int, int)>{};
    for (final i in library) {
      final cur = m[i.category] ?? (0, 0);
      m[i.category] = (cur.$1 + 1, cur.$2 + i.size);
    }
    return [for (final e in m.entries) (e.key, e.value.$1, e.value.$2)]..sort((a, b) => b.$2.compareTo(a.$2));
  }

  List<ActivityBucket> activity(StatsPeriod period, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    final buckets = <ActivityBucket>[];
    switch (period) {
      case StatsPeriod.daily:
        for (var i = 13; i >= 0; i--) {
          final d = today.subtract(Duration(days: i));
          buckets.add(ActivityBucket(d, '${d.day}/${d.month}'));
        }
      case StatsPeriod.weekly:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        for (var i = 11; i >= 0; i--) {
          final d = monday.subtract(Duration(days: 7 * i));
          buckets.add(ActivityBucket(d, '${d.day}/${d.month}'));
        }
      case StatsPeriod.monthly:
        for (var i = 11; i >= 0; i--) {
          final d = DateTime(today.year, today.month - i);
          buckets.add(ActivityBucket(d, '${d.month}/${d.year % 100}'));
        }
    }
    for (final e in _done) {
      for (var b = buckets.length - 1; b >= 0; b--) {
        if (!e.at.isBefore(buckets[b].start)) {
          final next = b + 1 < buckets.length ? buckets[b + 1].start : null;
          if (next == null || e.at.isBefore(next)) {
            if (e.direction == TransferDirection.incoming) {
              buckets[b].received += e.totalBytes;
            } else {
              buckets[b].sent += e.totalBytes;
            }
          }
          break;
        }
      }
    }
    // The last bucket must not swallow the future: drop entries after today.
    return buckets;
  }

  Map<String, Object?> toJson() => {
        'generated': DateTime.now().toIso8601String(),
        'filesReceived': filesReceived,
        'filesSent': filesSent,
        'bytesReceived': bytesReceived,
        'bytesSent': bytesSent,
        'transfers': transfers,
        'failed': failed,
        'averageSpeedBytesPerSecond': averageSpeed.round(),
        'peakSpeedBytesPerSecond': peakSpeed.round(),
        'topSenders': [for (final s in topSenders(20)) {'device': s.$1, 'files': s.$2, 'bytes': s.$3}],
        'categories': [for (final c in topCategories()) {'category': c.$1.folder, 'files': c.$2, 'bytes': c.$3}],
      };

  String toPrettyJson(List<HistoryEntry> entries) => const JsonEncoder.withIndent('  ').convert({
        'summary': toJson(),
        'transfers': [for (final e in entries) e.toJson()],
      });

  /// One row per transfer.
  String toCsv() {
    String q(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    final b = StringBuffer('time,direction,device,fingerprint,status,files,bytes,seconds,avg_bytes_per_s,peak_bytes_per_s,first_file\n');
    for (final e in history.reversed) {
      b.writeln([
        e.at.toIso8601String(),
        e.direction.name,
        q(nameOf(e)),
        e.fingerprint ?? '',
        e.status.name,
        e.fileCount,
        e.totalBytes,
        (e.transferMs / 1000).toStringAsFixed(1),
        e.avgSpeed.round(),
        e.peakSpeed.round(),
        q(e.firstName),
      ].join(','));
    }
    return b.toString();
  }
}
