import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudosend/app/strings.dart';
import 'package:sudosend/state/chat.dart';
import 'package:sudosend/state/settings.dart';
import 'package:wraith_core/util.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
  });

  test('every English string has an Arabic translation', () {
    expect(missingArabicKeys(), isEmpty);
  });

  test('placeholders are filled', () {
    expect(tr('en', 'to_name', {'name': 'Pi'}), 'To Pi');
    expect(tr('ar', 'to_name', {'name': 'Pi'}), 'إلى Pi');
    expect(tr('ar', 'does_not_exist'), 'does_not_exist');
  });

  test('sync pairs survive a round trip; broken entries are dropped', () {
    final pair = SyncPair(id: 'abc', name: 'Projects', path: '/tmp/p', fingerprint: 'F' * 32, peerName: 'Laptop')
      ..pushed = 3
      ..lastSync = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final back = SyncPair.fromJson(pair.toJson())!;
    expect(back.id, 'abc');
    expect(back.pushed, 3);
    expect(back.lastSync, pair.lastSync);
    expect(SyncPair.fromJson({'id': 1}), isNull);
  });

  test('chat threads persist, count unread and cap their length', () async {
    final dir = await Directory.systemTemp.createTemp('sudosend_chat_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await ChatStore.load(dir);
    store.add('FP', 'Phone', 'hi', outgoing: false, unread: true);
    final out = store.add('FP', 'Phone', 'hello', outgoing: true);
    expect(out.state, ChatState.sending);
    expect(store.unread, 1);
    for (var i = 0; i < ChatStore.maxPerThread + 5; i++) {
      store.add('FP', 'Phone', '$i', outgoing: true);
    }
    await store.save();
    final again = await ChatStore.load(dir);
    final t = again.threads['FP']!;
    expect(t.messages, hasLength(ChatStore.maxPerThread));
    expect(t.unread, 1);
    // A message still "sending" when the app closed is shown as failed (retryable).
    expect(t.messages.last.state, ChatState.failed);
  });
}
