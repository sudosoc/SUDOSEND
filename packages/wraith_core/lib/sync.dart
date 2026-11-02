// Folder sync — two-way, newest-wins, with an archive instead of data loss.
//
// Each side periodically asks the other for a manifest of its sync folder
// (relative path, size, modification time) and *pushes* the files it has
// that the other side lacks or holds an older copy of. Both sides doing this
// gives two-way sync. Received files keep the sender's modification time, so
// the next comparison sees them as equal and nothing ping-pongs.
//
// Before a file is overwritten, the previous version is moved to
// `.sudosend-archive/<timestamp>/` inside the sync folder. Deletions are not
// propagated (a mistaken delete must never wipe the other device).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';

const String kSyncArchive = '.sudosend-archive';

class ManifestEntry {
  const ManifestEntry(this.path, this.size, this.mtime);
  final String path; // relative, '/' separators
  final int size;
  final int mtime; // ms since epoch

  Map<String, Object> toJson() => {'p': path, 's': size, 'm': mtime};
  static ManifestEntry fromJson(Map<String, dynamic> m) =>
      ManifestEntry(m['p'] as String, m['s'] as int, m['m'] as int);
}

bool _hidden(String segment) => segment.startsWith('.');

/// Lists every regular file under [root] (skipping hidden entries, partial
/// downloads and the archive). Capped at [limit] files.
Future<List<ManifestEntry>> buildManifest(Directory root, {int limit = 50000}) async {
  final out = <ManifestEntry>[];
  if (!await root.exists()) return out;
  await for (final e in root.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: root.path);
    final parts = p.split(rel);
    if (parts.any(_hidden)) continue;
    final stat = await e.stat();
    out.add(ManifestEntry(parts.join('/'), stat.size, stat.modified.millisecondsSinceEpoch));
    if (out.length >= limit) break;
  }
  return out;
}

/// Files this side should push: missing on the other side, or newer here.
/// Modification times within 2 s are treated as equal (FAT/exFAT precision).
List<ManifestEntry> planPush(List<ManifestEntry> local, List<ManifestEntry> remote) {
  final theirs = {for (final r in remote) r.path: r};
  return [
    for (final l in local)
      if (theirs[l.path] == null || l.mtime - theirs[l.path]!.mtime > 2000) l,
  ];
}

String encodeManifest(List<ManifestEntry> m) =>
    base64Encode(gzip.encode(utf8.encode(jsonEncode([for (final e in m) e.toJson()]))));

List<ManifestEntry> decodeManifest(String b64) {
  final raw = gzip.decode(base64Decode(b64));
  if (raw.length > 64 * 1024 * 1024) throw const WraithException('Manifest too large');
  return [for (final e in jsonDecode(utf8.decode(raw)) as List<dynamic>) ManifestEntry.fromJson(e as Map<String, dynamic>)];
}

/// Moves an existing file into the archive before it is overwritten.
/// Where [existing] goes in the archive if it is replaced now.
String archivePathFor(Directory root, File existing) {
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  final rel = p.relative(existing.path, from: root.path);
  return p.join(root.path, kSyncArchive, stamp, rel);
}

/// Moves an existing file into the archive before it is overwritten.
/// Returns where it went (null if there was nothing to archive).
Future<String?> archiveExisting(Directory root, File existing, {String? to}) async {
  if (!await existing.exists()) return null;
  final dest = File(to ?? archivePathFor(root, existing));
  await dest.parent.create(recursive: true);
  await existing.rename(dest.path);
  return dest.path;
}
