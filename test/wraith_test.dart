import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sudosend/core/identity.dart';
import 'package:sudosend/core/models.dart';
import 'package:sudosend/core/transfer.dart';
import 'package:sudosend/core/util.dart';

void main() {
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
}
