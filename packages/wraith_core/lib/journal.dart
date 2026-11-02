// Smart Recovery: a write-ahead journal for file operations that touch more
// than one path (replace with archive, move to trash, restore). Each step is
// written and flushed *before* the file system is changed; when the step is
// done an "end" record follows. After a crash, [recoverJournal] looks at the
// operations that never ended and puts the files back into a stable state —
// never deleting anything it is unsure about.

import 'dart:convert';
import 'dart:io';

class JournalOp {
  JournalOp(this.id, this.kind, this.data, this.at);
  final String id;

  /// replace | move
  final String kind;
  final Map<String, dynamic> data;
  final DateTime at;
}

class Journal {
  Journal(this.file);
  final File file;
  int _seq = 0;

  /// Records an operation that is about to start. Synchronous on purpose:
  /// the record must be on disk before the file system changes.
  String begin(String kind, Map<String, Object?> data) {
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    _append({'op': 'begin', 'id': id, 'kind': kind, 'at': DateTime.now().toIso8601String(), ...data});
    return id;
  }

  void end(String id) => _append({'op': 'end', 'id': id});

  void _append(Map<String, Object?> m) {
    try {
      file.parent.createSync(recursive: true);
      final raf = file.openSync(mode: FileMode.append);
      raf.writeStringSync('${jsonEncode(m)}\n');
      raf.flushSync();
      raf.closeSync();
    } catch (_) {}
  }

  /// Operations that began but never ended.
  List<JournalOp> pending() {
    final open = <String, JournalOp>{};
    try {
      if (!file.existsSync()) return const [];
      for (final line in file.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        try {
          final m = jsonDecode(line) as Map<String, dynamic>;
          final id = m['id'] as String;
          if (m['op'] == 'begin') {
            open[id] = JournalOp(id, m['kind'] as String, m, DateTime.tryParse(m['at'] as String? ?? '') ?? DateTime.now());
          } else {
            open.remove(id);
          }
        } catch (_) {
          // A torn last line from a crash: ignore it.
        }
      }
    } catch (_) {}
    return open.values.toList();
  }

  /// Keeps only unfinished operations (call after recovery).
  void compact() {
    try {
      final keep = pending();
      if (keep.isEmpty) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.writeAsStringSync(keep.map((o) => '${jsonEncode({'op': 'begin', 'id': o.id, 'kind': o.kind, ...o.data})}\n').join());
    } catch (_) {}
  }
}

/// Moves [from] to [to] (rename, or copy + delete across volumes).
Future<void> movePath(String from, String to) async {
  await Directory(File(to).parent.path).create(recursive: true);
  try {
    await File(from).rename(to);
  } on FileSystemException {
    await File(from).copy(to);
    await File(from).delete();
  }
}

class RecoveryResult {
  final List<String> repaired = [];
  final List<String> needsAttention = [];
}

/// Brings every unfinished operation to a stable state.
///  replace {dest, archived}: dest missing but archived present → restore it.
///  move {from, to}:  only `to` exists → done; only `from` → not started;
///                    both (interrupted copy) → keep `from`, drop the partial
///                    `to` only if it is smaller; otherwise keep both.
Future<RecoveryResult> recoverJournal(Journal j) async {
  final r = RecoveryResult();
  for (final op in j.pending()) {
    try {
      switch (op.kind) {
        case 'replace':
          final dest = File(op.data['dest'] as String);
          final archived = File(op.data['archived'] as String);
          if (!dest.existsSync() && archived.existsSync()) {
            await movePath(archived.path, dest.path);
            r.repaired.add('restored ${dest.path}');
          }
        case 'move':
          final from = File(op.data['from'] as String);
          final to = File(op.data['to'] as String);
          if (from.existsSync() && to.existsSync()) {
            if (to.lengthSync() < from.lengthSync()) {
              to.deleteSync();
              r.repaired.add('removed partial copy ${to.path}');
            } else {
              r.needsAttention.add('two copies: ${from.path} and ${to.path}');
            }
          }
      }
    } catch (e) {
      r.needsAttention.add('${op.kind}: $e');
    }
    j.end(op.id);
  }
  j.compact();
  return r;
}
