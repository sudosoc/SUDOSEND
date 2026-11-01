import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// What happened. Kept short and stable: exported logs are read by people
/// and by scripts.
enum AuditKind {
  connectionRejected, // flood limits, blocked device
  requestAccepted,
  requestDeclined,
  transferDone,
  transferFailed,
  deviceTrusted,
  deviceUntrusted,
  deviceBlocked,
  deviceUnblocked,
  trustExpired,
  permissionDenied, // a device asked for something its profile does not allow
  fileDeleted,
  duplicateFound,
  riskyFile,
  storageLow,
  settingsChanged,
}

class AuditEvent {
  AuditEvent(this.at, this.kind, {this.device, this.detail});
  final DateTime at;
  final AuditKind kind;
  final String? device;
  final String? detail;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'event': kind.name,
        if (device != null) 'device': device,
        if (detail != null) 'detail': detail,
      };

  static AuditEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return AuditEvent(
        DateTime.parse(raw['at'] as String),
        AuditKind.values.byName(raw['event'] as String),
        device: raw['device'] as String?,
        detail: raw['detail'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Append-only security log (audit.jsonl in app data), newest kept up to
/// [limit] events. One JSON object per line, so it is easy to grep or feed
/// to a SIEM.
class AuditLog {
  AuditLog._(this._file);
  final File _file;
  final List<AuditEvent> events = []; // newest first
  static const int limit = 5000;

  static Future<AuditLog> load(Directory dir) async {
    final log = AuditLog._(File(p.join(dir.path, 'audit.jsonl')));
    try {
      if (await log._file.exists()) {
        final lines = await log._file.readAsLines();
        for (final l in lines.reversed) {
          if (l.trim().isEmpty) continue;
          try {
            final e = AuditEvent.fromJson(jsonDecode(l));
            if (e != null) log.events.add(e);
          } catch (_) {}
          if (log.events.length >= limit) break;
        }
      }
    } catch (_) {}
    return log;
  }

  Future<void> _pending = Future<void>.value();
  int _sinceCompact = 0;

  void add(AuditKind kind, {String? device, String? detail}) {
    final e = AuditEvent(DateTime.now(), kind, device: device, detail: detail);
    events.insert(0, e);
    if (events.length > limit) events.removeRange(limit, events.length);
    _pending = _pending.then((_) async {
      try {
        await _file.parent.create(recursive: true);
        if (++_sinceCompact >= 500) {
          // Rewrite occasionally so the file stays bounded.
          _sinceCompact = 0;
          await _file.writeAsString('${events.reversed.map((e) => jsonEncode(e.toJson())).join('\n')}\n');
        } else {
          await _file.writeAsString('${jsonEncode(e.toJson())}\n', mode: FileMode.append);
        }
      } catch (_) {}
    });
  }

  String exportJsonl() => '${events.reversed.map((e) => jsonEncode(e.toJson())).join('\n')}\n';

  String exportCsv() {
    String q(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    final b = StringBuffer('time,event,device,detail\n');
    for (final e in events.reversed) {
      b.writeln('${e.at.toIso8601String()},${e.kind.name},${q(e.device)},${q(e.detail)}');
    }
    return b.toString();
  }
}
