import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wraith_core/models.dart';

/// A transfer waiting for a trusted device to come online.
class OutboxItem {
  OutboxItem({
    required this.id,
    required this.fingerprint,
    required this.peerName,
    required this.files,
    required this.created,
    this.text,
    this.attempts = 0,
    this.lastError,
    this.hotPaths = const [],
  });

  factory OutboxItem.fromJson(Map<String, dynamic> m) => OutboxItem(
        id: m['id'] as String,
        fingerprint: m['fp'] as String,
        peerName: m['name'] as String,
        files: [
          for (final f in (m['files'] as List<dynamic>))
            FileEntry(name: f['name'] as String, size: f['size'] as int, path: f['path'] as String),
        ],
        text: m['text'] as String?,
        created: DateTime.parse(m['created'] as String),
        attempts: (m['attempts'] as int?) ?? 0,
        lastError: m['error'] as String?,
        hotPaths: [for (final h in (m['hot'] as List<dynamic>? ?? const [])) h as String],
      );

  final String id;
  final String fingerprint;
  final String peerName;
  final List<FileEntry> files;
  final String? text;
  final DateTime created;
  int attempts;
  String? lastError;

  /// Hot-folder entries to move into "Sent" after delivery.
  final List<String> hotPaths;

  int get totalBytes => files.fold<int>(0, (a, f) => a + f.size);

  Map<String, Object?> toJson() => {
        'id': id,
        'fp': fingerprint,
        'name': peerName,
        'files': [for (final f in files) {'name': f.name, 'size': f.size, 'path': f.path}],
        'text': text,
        'created': created.toIso8601String(),
        'attempts': attempts,
        'error': lastError,
        'hot': hotPaths,
      };
}

class OutboxStore {
  OutboxStore._(this._file, this.items);

  final File _file;
  final List<OutboxItem> items;

  static Future<OutboxStore> load(Directory dir) async {
    final file = File(p.join(dir.path, 'outbox.json'));
    final items = <OutboxItem>[];
    try {
      if (await file.exists()) {
        for (final e in jsonDecode(await file.readAsString()) as List<dynamic>) {
          try {
            items.add(OutboxItem.fromJson(e as Map<String, dynamic>));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return OutboxStore._(file, items);
  }

  Future<void> add(OutboxItem item) async {
    items.add(item);
    await save();
  }

  Future<void> remove(String id) async {
    items.removeWhere((i) => i.id == id);
    await save();
  }

  Future<void> save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode([for (final i in items) i.toJson()]));
    } catch (_) {}
  }
}
