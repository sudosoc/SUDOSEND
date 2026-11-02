import 'dart:convert';
import 'dart:io';

/// Crash-safe storage for SUDOSEND's own data files (settings, history,
/// library, devices, chat, outbox). A save writes a temp file, keeps the
/// previous version as `.bak`, then renames the temp file into place, so a
/// crash or power cut mid-save never leaves a half-written file behind. A
/// load falls back to `.bak` when the main file is missing or unreadable.
class SafeFile {
  /// Files restored from their backup since the app started (Recovery screen).
  static final List<String> restored = [];

  static final Map<String, Future<void>> _chains = {};

  /// Saves of the same file run one after another.
  static Future<void> write(File f, String content) {
    final next = (_chains[f.path] ?? Future<void>.value()).then((_) => _write(f, content)).catchError((Object _) {});
    _chains[f.path] = next;
    return next;
  }

  static Future<void> _write(File f, String content) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    final bak = File('${f.path}.bak');
    if (await f.exists()) {
      try {
        if (await bak.exists()) await bak.delete();
        await f.rename(bak.path);
      } catch (_) {}
    }
    await tmp.rename(f.path);
  }

  /// Reads and decodes [f]; on any failure tries `f.bak`. Null if neither works.
  static Future<T?> readJson<T>(File f, T Function(Object? json) parse) async {
    for (final candidate in [f, File('${f.path}.bak')]) {
      try {
        if (!await candidate.exists()) continue;
        final value = parse(jsonDecode(await candidate.readAsString()));
        if (!identical(candidate, f)) restored.add(f.path);
        return value;
      } catch (_) {}
    }
    return null;
  }
}
