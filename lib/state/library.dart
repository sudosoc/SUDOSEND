import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:wraith_core/organize.dart';

/// One received file, as SUDOSEND knows it.
class LibraryItem {
  LibraryItem({
    required this.path,
    required this.name,
    required this.size,
    required this.sha256,
    required this.receivedAt,
    required this.device,
    this.fingerprint,
    this.duplicateOf,
  }) : category = categorize(name);

  final String path;
  final String name;
  final int size;
  final String sha256; // hex
  final DateTime receivedAt;
  final String device;
  final String? fingerprint;
  final FileCategory category;

  /// Path of an identical file that was already here when this one arrived.
  String? duplicateOf;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  Map<String, Object?> toJson() => {
        'p': path,
        'n': name,
        's': size,
        'h': sha256,
        'at': receivedAt.millisecondsSinceEpoch,
        'd': device,
        if (fingerprint != null) 'fp': fingerprint,
        if (duplicateOf != null) 'dup': duplicateOf,
      };

  static LibraryItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return LibraryItem(
        path: raw['p'] as String,
        name: raw['n'] as String,
        size: (raw['s'] as num).toInt(),
        sha256: raw['h'] as String,
        receivedAt: DateTime.fromMillisecondsSinceEpoch((raw['at'] as num).toInt()),
        device: raw['d'] as String? ?? '?',
        fingerprint: raw['fp'] as String?,
        duplicateOf: raw['dup'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Filters for the Files screen.
class LibraryQuery {
  const LibraryQuery({
    this.text = '',
    this.category,
    this.device,
    this.from,
    this.to,
    this.minSize,
    this.maxSize,
    this.duplicatesOnly = false,
    this.sort = 'newest',
  });

  /// Matches name and extension; "ext:pdf" or ".pdf" match the extension only.
  final String text;
  final FileCategory? category;
  final String? device;
  final DateTime? from;
  final DateTime? to; // inclusive day
  final int? minSize;
  final int? maxSize;
  final bool duplicatesOnly;

  /// newest | oldest | largest | smallest | name
  final String sort;

  bool get isEmpty =>
      text.isEmpty && category == null && device == null && from == null && to == null &&
      minSize == null && maxSize == null && !duplicatesOnly;

  LibraryQuery copyWith({
    String? text,
    FileCategory? Function()? category,
    String? Function()? device,
    DateTime? Function()? from,
    DateTime? Function()? to,
    int? Function()? minSize,
    int? Function()? maxSize,
    bool? duplicatesOnly,
    String? sort,
  }) =>
      LibraryQuery(
        text: text ?? this.text,
        category: category != null ? category() : this.category,
        device: device != null ? device() : this.device,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
        minSize: minSize != null ? minSize() : this.minSize,
        maxSize: maxSize != null ? maxSize() : this.maxSize,
        duplicatesOnly: duplicatesOnly ?? this.duplicatesOnly,
        sort: sort ?? this.sort,
      );
}

/// Index of received files: powers search, the timeline, previews, duplicate
/// detection, storage and statistics. Stored as library.json in app data.
class LibraryStore {
  LibraryStore._(this._file, this.items);

  static const int limit = 50000;
  final File _file;

  /// Newest first.
  final List<LibraryItem> items;
  final Map<String, List<LibraryItem>> _byHash = {};

  static Future<LibraryStore> load(Directory dir) async {
    final file = File(p.join(dir.path, 'library.json'));
    final items = <LibraryItem>[];
    try {
      if (await file.exists()) {
        final raw = await compute(_decode, await file.readAsString());
        items.addAll(raw.map(LibraryItem.fromJson).whereType<LibraryItem>());
      }
    } catch (_) {}
    final store = LibraryStore._(file, items);
    store._reindex();
    return store;
  }

  static List<dynamic> _decode(String s) => jsonDecode(s) as List<dynamic>;

  void _reindex() {
    _byHash.clear();
    for (final i in items) {
      (_byHash[i.sha256] ??= []).add(i);
    }
  }

  /// Other indexed files with the same content as [sha256], still on disk.
  List<LibraryItem> sameContent(String sha256, {String? except}) =>
      [for (final i in _byHash[sha256] ?? const <LibraryItem>[]) if (i.path != except && File(i.path).existsSync()) i];

  /// Adds a received file. Returns the existing identical file, if any.
  LibraryItem? add(LibraryItem item) {
    final twin = sameContent(item.sha256, except: item.path).firstOrNull;
    if (twin != null) item.duplicateOf = twin.path;
    items.removeWhere((i) => i.path == item.path);
    items.insert(0, item);
    (_byHash[item.sha256] ??= []).add(item);
    if (items.length > limit) {
      items.removeRange(limit, items.length);
      _reindex();
    }
    return twin;
  }

  void remove(String path) {
    items.removeWhere((i) => i.path == path);
    _reindex();
  }

  /// Drops entries whose file was deleted or moved outside SUDOSEND.
  int prune() {
    final before = items.length;
    items.removeWhere((i) => !File(i.path).existsSync());
    if (items.length != before) _reindex();
    return before - items.length;
  }

  bool contains(String path) => items.any((i) => i.path == path);

  /// Groups of identical files (2+ copies still on disk), biggest waste first.
  List<List<LibraryItem>> duplicateGroups() {
    final groups = [
      for (final g in _byHash.values)
        if (g.length > 1) g.where((i) => File(i.path).existsSync()).toList(),
    ].where((g) => g.length > 1).toList()
      ..sort((a, b) => (b.first.size * (b.length - 1)).compareTo(a.first.size * (a.length - 1)));
    return groups;
  }

  List<LibraryItem> search(LibraryQuery q) {
    var t = q.text.trim().toLowerCase();
    String? ext;
    if (t.startsWith('ext:')) {
      ext = t.substring(4).replaceAll('.', '');
      t = '';
    } else if (t.startsWith('.') && !t.contains(' ')) {
      ext = t.substring(1);
      t = '';
    }
    final to = q.to == null ? null : DateTime(q.to!.year, q.to!.month, q.to!.day).add(const Duration(days: 1));
    final out = items.where((i) {
      if (q.category != null && i.category != q.category) return false;
      if (q.device != null && i.device != q.device) return false;
      if (q.from != null && i.receivedAt.isBefore(q.from!)) return false;
      if (to != null && !i.receivedAt.isBefore(to)) return false;
      if (q.minSize != null && i.size < q.minSize!) return false;
      if (q.maxSize != null && i.size > q.maxSize!) return false;
      if (q.duplicatesOnly && i.duplicateOf == null && (_byHash[i.sha256]?.length ?? 0) < 2) return false;
      if (ext != null && i.extension != ext) return false;
      if (t.isNotEmpty && !i.name.toLowerCase().contains(t) && !i.device.toLowerCase().contains(t)) return false;
      return true;
    }).toList();
    switch (q.sort) {
      case 'oldest':
        out.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
      case 'largest':
        out.sort((a, b) => b.size.compareTo(a.size));
      case 'smallest':
        out.sort((a, b) => a.size.compareTo(b.size));
      case 'name':
        out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      default:
        out.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    }
    return out;
  }

  List<String> get devices => {for (final i in items) i.device}.toList()..sort();

  Future<void> _pending = Future<void>.value();

  Future<void> save() => _pending = _pending.then((_) async {
        try {
          await _file.parent.create(recursive: true);
          final data = await compute(_encode, [for (final i in items) i.toJson()]);
          await _file.writeAsString(data);
        } catch (_) {}
      });

  static String _encode(List<Map<String, Object?>> l) => jsonEncode(l);

  /// Indexes files already in [root] that SUDOSEND does not know yet
  /// (received before this feature, or copied in). Hashing runs in the
  /// background; [onProgress] gets (done, total).
  Future<int> scan(Directory root, {void Function(int done, int total)? onProgress}) async {
    if (!await root.exists()) return 0;
    final known = {for (final i in items) i.path};
    final found = <File>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: root.path);
      if (p.split(rel).any((s) => s.startsWith('.'))) continue;
      if (!known.contains(e.path)) found.add(e);
    }
    var done = 0;
    for (final f in found) {
      try {
        final hash = await compute(hashFile, f.path);
        final stat = await f.stat();
        final rel = p.split(p.relative(f.path, from: root.path));
        add(LibraryItem(
          path: f.path,
          name: p.basename(f.path),
          size: stat.size,
          sha256: hash,
          receivedAt: stat.modified,
          device: rel.length > 1 && !_notDevice.contains(rel.first) && !_date.hasMatch(rel.first) ? rel.first : '?',
        ));
      } catch (_) {}
      done++;
      onProgress?.call(done, found.length);
    }
    items.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    await save();
    return found.length;
  }
}

final Set<String> _notDevice = {for (final c in FileCategory.values) c.folder, kFoldersFolder};
final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// SHA-256 of a file (hex), streamed. Top-level so it can run in an isolate.
Future<String> hashFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}
