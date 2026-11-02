import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'safe_file.dart';

enum ChatState { sending, sent, failed, received }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.text,
    required this.outgoing,
    required this.at,
    required this.state,
  });

  final String id;
  final String text;
  final bool outgoing;
  final DateTime at;
  ChatState state;

  Map<String, Object> toJson() => {
        'id': id,
        't': text,
        'o': outgoing,
        'at': at.millisecondsSinceEpoch,
        's': state == ChatState.sending ? ChatState.failed.name : state.name,
      };

  static ChatMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return ChatMessage(
        id: raw['id'] as String,
        text: raw['t'] as String,
        outgoing: raw['o'] as bool,
        at: DateTime.fromMillisecondsSinceEpoch(raw['at'] as int),
        state: ChatState.values.byName(raw['s'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

class ChatThread {
  ChatThread(this.fingerprint, this.peerName);
  final String fingerprint;
  String peerName;
  int unread = 0;
  final List<ChatMessage> messages = [];

  DateTime get lastAt => messages.isEmpty ? DateTime.fromMillisecondsSinceEpoch(0) : messages.last.at;
}

/// Message threads per trusted device, stored locally in chat.json (in the
/// app's private folder; messages travel end-to-end encrypted like files).
class ChatStore {
  ChatStore._(this._file);
  final File _file;
  final Map<String, ChatThread> threads = {};
  static const int maxPerThread = 500;

  static Future<ChatStore> load(Directory dir) async {
    final store = ChatStore._(File(p.join(dir.path, 'chat.json')));
    try {
      final m = await SafeFile.readJson(store._file, (j) => j as Map<String, dynamic>);
      if (m != null) {
        for (final e in m.entries) {
          final v = e.value as Map<String, dynamic>;
          final t = ChatThread(e.key, v['name'] as String? ?? '?')..unread = v['unread'] as int? ?? 0;
          t.messages.addAll((v['m'] as List<dynamic>).map(ChatMessage.fromJson).whereType<ChatMessage>());
          store.threads[e.key] = t;
        }
      }
    } catch (_) {}
    return store;
  }

  List<ChatThread> get sorted => threads.values.toList()..sort((a, b) => b.lastAt.compareTo(a.lastAt));
  int get unread => threads.values.fold(0, (a, t) => a + t.unread);

  ChatThread thread(String fingerprint, String name) {
    final t = threads.putIfAbsent(fingerprint, () => ChatThread(fingerprint, name));
    t.peerName = name;
    return t;
  }

  ChatMessage add(String fingerprint, String name, String text, {required bool outgoing, bool unread = false}) {
    final t = thread(fingerprint, name);
    final msg = ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      outgoing: outgoing,
      at: DateTime.now(),
      state: outgoing ? ChatState.sending : ChatState.received,
    );
    t.messages.add(msg);
    if (t.messages.length > maxPerThread) t.messages.removeRange(0, t.messages.length - maxPerThread);
    if (unread) t.unread++;
    save();
    return msg;
  }

  void markRead(String fingerprint) {
    final t = threads[fingerprint];
    if (t == null || t.unread == 0) return;
    t.unread = 0;
    save();
  }

  void clear(String fingerprint) {
    threads.remove(fingerprint);
    save();
  }

  Future<void> _pending = Future<void>.value();

  /// Writes are chained so two quick saves never interleave on disk.
  Future<void> save() => _pending = _pending.then((_) => _write());

  Future<void> _write() async {
    try {
      await SafeFile.write(_file, jsonEncode({
        for (final t in threads.values)
          t.fingerprint: {
            'name': t.peerName,
            'unread': t.unread,
            'm': [for (final m in t.messages) m.toJson()],
          },
      }));
    } catch (_) {}
  }
}
