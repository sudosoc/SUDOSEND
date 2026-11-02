import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wraith_core/journal.dart';

import 'safe_file.dart';

class TrashItem {
  TrashItem({required this.id, required this.original, required this.stored, required this.at, required this.size});
  final String id;
  final String original;
  final String stored;
  final DateTime at;
  final int size;

  String get name => p.basename(original);

  Map<String, Object> toJson() =>
      {'id': id, 'orig': original, 'stored': stored, 'at': at.millisecondsSinceEpoch, 'size': size};

  static TrashItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return TrashItem(
        id: raw['id'] as String,
        original: raw['orig'] as String,
        stored: raw['stored'] as String,
        at: DateTime.fromMillisecondsSinceEpoch((raw['at'] as num).toInt()),
        size: (raw['size'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Deleted files wait here before they are really gone (Smart Recovery).
/// Files live in `<inbox>/.sudosend-trash/<id>/name`; every move is journaled.
class TrashStore {
  TrashStore._(this._file, this.journal);
  final File _file;
  final Journal journal;
  final List<TrashItem> items = []; // newest first

  static Future<TrashStore> load(Directory support, Journal journal) async {
    final t = TrashStore._(File(p.join(support.path, 'trash.json')), journal);
    final list = await SafeFile.readJson(t._file, (j) => j as List<dynamic>);
    if (list != null) t.items.addAll(list.map(TrashItem.fromJson).whereType<TrashItem>());
    t.items.removeWhere((i) => !File(i.stored).existsSync());
    return t;
  }

  int get totalBytes => items.fold(0, (a, i) => a + i.size);

  Future<TrashItem> put(String path, Directory inbox) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final stored = p.join(inbox.path, '.sudosend-trash', id, p.basename(path));
    final size = await File(path).length();
    final op = journal.begin('move', {'from': path, 'to': stored});
    await movePath(path, stored);
    journal.end(op);
    final item = TrashItem(id: id, original: path, stored: stored, at: DateTime.now(), size: size);
    items.insert(0, item);
    await save();
    return item;
  }

  /// Puts the file back where it was (or next to it if that name is taken).
  Future<String> restore(TrashItem item) async {
    var target = item.original;
    var n = 1;
    while (File(target).existsSync()) {
      target = p.join(p.dirname(item.original),
          '${p.basenameWithoutExtension(item.original)} ($n)${p.extension(item.original)}');
      n++;
    }
    final op = journal.begin('move', {'from': item.stored, 'to': target});
    await movePath(item.stored, target);
    journal.end(op);
    await _dropDir(item);
    items.remove(item);
    await save();
    return target;
  }

  Future<void> delete(TrashItem item) async {
    try {
      final f = File(item.stored);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _dropDir(item);
    items.remove(item);
    await save();
  }

  /// Removes items older than [days]. Returns how many.
  Future<int> purge(int days) async {
    final limit = DateTime.now().subtract(Duration(days: days));
    final old = items.where((i) => i.at.isBefore(limit)).toList();
    for (final i in old) {
      await delete(i);
    }
    return old.length;
  }

  Future<void> empty() async {
    for (final i in List.of(items)) {
      await delete(i);
    }
  }

  Future<void> _dropDir(TrashItem item) async {
    try {
      final dir = Directory(p.dirname(item.stored));
      if (await dir.exists() && (await dir.list().isEmpty)) await dir.delete();
    } catch (_) {}
  }

  Future<void> save() => SafeFile.write(_file, jsonEncode([for (final i in items) i.toJson()]));
}
