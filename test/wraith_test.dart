import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wraith_core/identity.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/transfer.dart';
import 'package:wraith_core/util.dart';

void main() {
  test('sanitizeRelativePath', () {
    expect(sanitizeRelativePath('../../a/./b/../c.txt'), ['a', 'b', 'c.txt']);
    expect(sanitizeRelativePath(r'C:\Windows\System32\x.dll'), ['C_', 'Windows', 'System32', 'x.dll']);
    expect(sanitizeRelativePath('..'), ['file']);
  });

  group('sanitizeFileName', () {
    test('blocks path traversal', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName(r'..\..\Windows\win.ini'), 'win.ini');
      expect(sanitizeFileName('/abs/path/report.pdf'), 'report.pdf');
    });
    test('neutralises dangerous names', () {
      expect(sanitizeFileName('..'), 'file');
      expect(sanitizeFileName('CON.txt'), '_CON.txt');
      expect(sanitizeFileName('a<b>c?.txt'), 'a_b_c_.txt');
    });
  });

  test('end-to-end encrypted transfer over loopback', () async {
    final tmp = await Directory.systemTemp.createTemp('sudosend_test_');
    addTearDown(() => tmp.delete(recursive: true));

    final alice = await DeviceIdentity.loadOrCreate(Directory(p.join(tmp.path, 'alice')));
    final bob = await DeviceIdentity.loadOrCreate(Directory(p.join(tmp.path, 'bob')));
    final inbox = await Directory(p.join(tmp.path, 'inbox')).create();

    String? receiverSas;
    final receiver = TransferEngine(
      identity: bob,
      trust: await TrustStore.load(Directory(p.join(tmp.path, 'bob'))),
      saveDir: () async => inbox,
      onIncoming: (r) {
        receiverSas = r.sas;
        r.respond(true);
      },
      onJob: (_) {},
      basePort: 0,
    );
    await receiver.start();
    addTearDown(receiver.stop);

    final payload = List<int>.generate(3 * 1024 * 1024 + 123, (i) => (i * 31) & 0xFF);
    final source = File(p.join(tmp.path, 'payload.bin'));
    await source.writeAsBytes(payload);

    TransferJob? job;
    final sender = TransferEngine(
      identity: alice,
      trust: await TrustStore.load(Directory(p.join(tmp.path, 'alice'))),
      saveDir: () async => tmp,
      onIncoming: (_) {},
      onJob: (j) => job = j,
      basePort: 0,
    );

    await sender.send(
      Peer(
        id: bob.fingerprint,
        name: bob.name,
        platform: 'linux',
        address: InternetAddress.loopbackIPv4,
        port: receiver.port,
        lastSeen: DateTime.now(),
      ),
      [FileEntry(name: 'payload.bin', size: payload.length, path: source.path)],
    );

    expect(job!.error, isNull);
    expect(job!.status, TransferStatus.done);
    expect(job!.sas, receiverSas, reason: 'both sides must derive the same SAS');
    expect(await File(p.join(inbox.path, 'payload.bin')).readAsBytes(), payload);
  });

  test('sender aborts when the fingerprint does not match discovery', () async {
    final tmp = await Directory.systemTemp.createTemp('sudosend_test_');
    addTearDown(() => tmp.delete(recursive: true));

    final alice = await DeviceIdentity.loadOrCreate(Directory(p.join(tmp.path, 'alice')));
    final bob = await DeviceIdentity.loadOrCreate(Directory(p.join(tmp.path, 'bob')));
    final receiver = TransferEngine(
      identity: bob,
      trust: await TrustStore.load(Directory(p.join(tmp.path, 'bob'))),
      saveDir: () async => tmp,
      onIncoming: (r) => r.respond(true),
      onJob: (_) {},
      basePort: 0,
    );
    await receiver.start();
    addTearDown(receiver.stop);

    final file = File(p.join(tmp.path, 'x.txt'))..writeAsStringSync('hello');
    TransferJob? job;
    final sender = TransferEngine(
      identity: alice,
      trust: await TrustStore.load(Directory(p.join(tmp.path, 'alice'))),
      saveDir: () async => tmp,
      onIncoming: (_) {},
      onJob: (j) => job = j,
      basePort: 0,
    );
    await sender.send(
      Peer(
        id: 'F' * 32, // advertised identity that bob does not own
        name: 'impostor',
        platform: 'linux',
        address: InternetAddress.loopbackIPv4,
        port: receiver.port,
        lastSeen: DateTime.now(),
      ),
      [FileEntry(name: 'x.txt', size: 5, path: file.path)],
    );
    expect(job!.status, TransferStatus.failed);
    expect(job!.error, contains('Fingerprint mismatch'));
  });

  test('resumes an interrupted transfer and still verifies the full hash', () async {
    final t = await _pair();
    final payload = List<int>.generate(2 * 1024 * 1024 + 77, (i) => (i * 7 + 3) & 0xFF);
    final source = File(p.join(t.tmp.path, 'movie.bin'))..writeAsBytesSync(payload);
    // Simulate the leftover of an earlier attempt that died after 1 MiB.
    const already = 1024 * 1024;
    File(p.join(t.inbox.path, '.movie.bin.${t.alice.fingerprint.substring(0, 8)}-${payload.length}.sudosend-part'))
        .writeAsBytesSync(payload.sublist(0, already));

    final job = await t.sender.send(t.peer, [FileEntry(name: 'movie.bin', size: payload.length, path: source.path)]);
    expect(job.error, isNull);
    expect(job.status, TransferStatus.done);
    expect(job.resumedBytes, already);
    expect(File(p.join(t.inbox.path, 'movie.bin')).readAsBytesSync(), payload);
  });

  test('a corrupted partial file is caught by SHA-256 and discarded', () async {
    final t = await _pair();
    final payload = List<int>.generate(600 * 1024, (i) => i & 0xFF);
    final source = File(p.join(t.tmp.path, 'doc.bin'))..writeAsBytesSync(payload);
    final part = File(p.join(t.inbox.path, '.doc.bin.${t.alice.fingerprint.substring(0, 8)}-${payload.length}.sudosend-part'))
      ..writeAsBytesSync(List<int>.filled(1000, 0x41)); // wrong bytes
    final job = await t.sender.send(t.peer, [FileEntry(name: 'doc.bin', size: payload.length, path: source.path)]);
    expect(job.status, TransferStatus.failed);
    expect(File(p.join(t.inbox.path, 'doc.bin')).existsSync(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(part.existsSync(), isFalse, reason: 'tampered partial must be deleted');
  });

  test('folders keep their structure and cannot escape the inbox', () async {
    final t = await _pair();
    final a = File(p.join(t.tmp.path, 'a.txt'))..writeAsStringSync('alpha');
    final b = File(p.join(t.tmp.path, 'b.txt'))..writeAsStringSync('bravo');
    final job = await t.sender.send(t.peer, [
      FileEntry(name: 'Album/2026/a.txt', size: 5, path: a.path),
      FileEntry(name: '../../../escape.txt', size: 5, path: b.path),
    ]);
    expect(job.status, TransferStatus.done);
    expect(File(p.join(t.inbox.path, 'Album', '2026', 'a.txt')).readAsStringSync(), 'alpha');
    expect(File(p.join(t.inbox.path, 'escape.txt')).readAsStringSync(), 'bravo');
    expect(File(p.join(t.tmp.path, 'escape.txt')).existsSync(), isFalse);
  });

  test('text messages arrive intact', () async {
    String? got;
    final t = await _pair(onIncoming: (r) {
      got = r.text;
      r.respond(true);
    });
    final job = await t.sender.send(t.peer, const [], text: 'كلمة السر: hunter2 🔐');
    expect(job.status, TransferStatus.done);
    expect(got, 'كلمة السر: hunter2 🔐');
  });

  test('declined transfers report declined', () async {
    final t = await _pair(onIncoming: (r) => r.respond(false));
    final f = File(p.join(t.tmp.path, 'x'))..writeAsStringSync('x');
    final job = await t.sender.send(t.peer, [FileEntry(name: 'x', size: 1, path: f.path)]);
    expect(job.status, TransferStatus.declined);
  });
}

class _Pair {
  _Pair(this.tmp, this.alice, this.bob, this.inbox, this.receiver, this.sender, this.peer);
  final Directory tmp;
  final DeviceIdentity alice;
  final DeviceIdentity bob;
  final Directory inbox;
  final TransferEngine receiver;
  final TransferEngine sender;
  final Peer peer;
}

Future<_Pair> _pair({void Function(IncomingRequest r)? onIncoming}) async {
  final tmp = await Directory.systemTemp.createTemp('sudosend_test_');
  addTearDown(() => tmp.delete(recursive: true));
  final alice = await DeviceIdentity.loadOrCreate(Directory(p.join(tmp.path, 'alice')));
  final bob = await DeviceIdentity.loadOrCreate(Directory(p.join(tmp.path, 'bob')));
  final inbox = await Directory(p.join(tmp.path, 'inbox')).create();
  final receiver = TransferEngine(
    identity: bob,
    trust: await TrustStore.load(Directory(p.join(tmp.path, 'bob'))),
    saveDir: () async => inbox,
    onIncoming: onIncoming ?? (r) => r.respond(true),
    onJob: (_) {},
    basePort: 0,
  );
  await receiver.start();
  addTearDown(receiver.stop);
  final sender = TransferEngine(
    identity: alice,
    trust: await TrustStore.load(Directory(p.join(tmp.path, 'alice'))),
    saveDir: () async => tmp,
    onIncoming: (_) {},
    onJob: (_) {},
    basePort: 0,
  );
  final peer = Peer(
    id: bob.fingerprint,
    name: bob.name,
    platform: 'linux',
    address: InternetAddress.loopbackIPv4,
    port: receiver.port,
    lastSeen: DateTime.now(),
  );
  return _Pair(tmp, alice, bob, inbox, receiver, sender, peer);
}
