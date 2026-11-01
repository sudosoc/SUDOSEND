import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudosend/app/strings.dart';
import 'package:sudosend/state/audit.dart';
import 'package:sudosend/state/chat.dart';
import 'package:sudosend/state/devices.dart';
import 'package:sudosend/state/history.dart';
import 'package:sudosend/state/library.dart';
import 'package:sudosend/state/stats.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/organize.dart';
import 'package:sudosend/state/settings.dart';
import 'package:sudosend/state/updater.dart';
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

  test('update version comparison', () {
    expect(Updater.isNewer('0.8.0', '0.7.0'), isTrue);
    expect(Updater.isNewer('0.10.0', '0.9.3'), isTrue);
    expect(Updater.isNewer('1.0.0', '0.99.99'), isTrue);
    expect(Updater.isNewer('0.8.0', '0.8.0'), isFalse);
    expect(Updater.isNewer('0.7.9', '0.8.0'), isFalse);
  });

  test('library finds identical files by SHA-256 even with another name, and searches', () async {
    final dir = await Directory.systemTemp.createTemp('sudosend_lib_');
    addTearDown(() => dir.delete(recursive: true));
    final a = File('${dir.path}/report.pdf')..writeAsStringSync('same bytes');
    final b = File('${dir.path}/copy of report.pdf')..writeAsStringSync('same bytes');
    final c = File('${dir.path}/photo.jpg')..writeAsStringSync('other');
    final store = await LibraryStore.load(dir);
    LibraryItem item(File f, String device, DateTime at) => LibraryItem(
          path: f.path,
          name: f.uri.pathSegments.last,
          size: f.lengthSync(),
          sha256: '',
          receivedAt: at,
          device: device,
        );
    final ha = await hashFile(a.path);
    expect(ha, await hashFile(b.path));
    expect(ha, isNot(await hashFile(c.path)));
    expect(store.add(LibraryItem(path: a.path, name: 'report.pdf', size: 10, sha256: ha, receivedAt: DateTime(2026, 11, 1), device: 'Laptop')), isNull);
    final twin = store.add(LibraryItem(path: b.path, name: 'copy of report.pdf', size: 10, sha256: ha, receivedAt: DateTime(2026, 11, 2), device: 'Phone'));
    expect(twin?.path, a.path);
    store.add(item(c, 'Phone', DateTime(2026, 11, 2)));
    expect(store.duplicateGroups(), hasLength(1));
    expect(store.search(const LibraryQuery(text: '.pdf')), hasLength(2));
    expect(store.search(const LibraryQuery(category: FileCategory.pictures)).single.name, 'photo.jpg');
    expect(store.search(const LibraryQuery(device: 'Laptop')), hasLength(1));
    expect(store.search(LibraryQuery(from: DateTime(2026, 11, 2), to: DateTime(2026, 11, 2))), hasLength(2));
    expect(store.search(const LibraryQuery(duplicatesOnly: true)), hasLength(2));
    expect(store.search(const LibraryQuery(sort: 'name')).first.name, 'copy of report.pdf');
    await store.save();
    final again = await LibraryStore.load(dir);
    expect(again.items, hasLength(3));
    expect(again.duplicateGroups(), hasLength(1));
    b.deleteSync();
    expect(again.prune(), 1);
    expect(again.duplicateGroups(), isEmpty);
  });

  test('device registry merges short gaps into one session', () async {
    final dir = await Directory.systemTemp.createTemp('sudosend_dev_');
    addTearDown(() => dir.delete(recursive: true));
    final r = await DeviceRegistry.load(dir);
    expect(r.seen('F' * 32, name: 'Phone', platform: 'android', address: '10.0.0.5', port: 47824), isTrue);
    expect(r.seen('F' * 32, name: 'Phone 2', platform: 'android'), isFalse);
    expect(r['F' * 32]!.sessions, hasLength(1));
    expect(r['F' * 32]!.name, 'Phone 2');
    expect(r['F' * 32]!.lastAddress, '10.0.0.5');
    await r.save();
    expect((await DeviceRegistry.load(dir))['F' * 32]!.sessions, hasLength(1));
  });

  test('audit log persists and exports', () async {
    final dir = await Directory.systemTemp.createTemp('sudosend_audit_');
    addTearDown(() => dir.delete(recursive: true));
    final log = await AuditLog.load(dir);
    log.add(AuditKind.connectionRejected, detail: '10.0.0.9 · flood');
    log.add(AuditKind.deviceTrusted, device: 'Laptop, "work"');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final again = await AuditLog.load(dir);
    expect(again.events.map((e) => e.kind), [AuditKind.deviceTrusted, AuditKind.connectionRejected]);
    expect(again.exportCsv(), contains('"Laptop, ""work"""'));
    expect(again.exportJsonl().trim().split('\n'), hasLength(2));
  });

  test('stats: totals, speeds, top senders and activity buckets', () {
    HistoryEntry e(TransferDirection d, String peer, int bytes, DateTime at, {int ms = 1000, double peak = 0}) => HistoryEntry(
          id: '$peer$at$bytes',
          direction: d,
          peerName: peer,
          peerPlatform: 'android',
          fileCount: 2,
          totalBytes: bytes,
          status: TransferStatus.done,
          isText: false,
          at: at,
          transferMs: ms,
          peakSpeed: peak,
        );
    final now = DateTime(2026, 11, 2, 12);
    final st = Stats([
      e(TransferDirection.incoming, 'Phone', 3000, now, peak: 9000),
      e(TransferDirection.incoming, 'Laptop', 1000, now.subtract(const Duration(days: 1))),
      e(TransferDirection.outgoing, 'Laptop', 2000, now, ms: 2000),
    ], const [], nameOf: (h) => h.peerName);
    expect(st.filesReceived, 4);
    expect(st.bytesReceived, 4000);
    expect(st.bytesSent, 2000);
    expect(st.averageSpeed, 6000 * 1000 / 4000);
    expect(st.peakSpeed, 9000);
    expect(st.topSenders().first.$1, 'Phone');
    final days = st.activity(StatsPeriod.daily, now: now);
    expect(days, hasLength(14));
    expect(days.last.received, 3000);
    expect(days.last.sent, 2000);
    expect(days[12].received, 1000);
    expect(st.toCsv().trim().split('\n'), hasLength(4));
  });
}
