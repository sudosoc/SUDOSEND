import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wraith_core/identity.dart';
import 'package:cryptography/cryptography.dart';
import 'package:wraith_core/aead.dart';
import 'package:wraith_core/chacha_poly.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/pairing.dart';
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

  group('ChaCha20-Poly1305 (fast implementation)', () {
    Uint8List hex(String h) {
      final clean = h.replaceAll(RegExp(r'\s'), '');
      return Uint8List.fromList([for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16)]);
    }

    test('RFC 8439 §2.8.2 AEAD test vector', () {
      final key = hex('808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f');
      final nonce = hex('070000004041424344454647');
      final aad = hex('50515253c0c1c2c3c4c5c6c7');
      final pt = Uint8List.fromList(
          "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
              .codeUnits);
      final sealed = ChaCha20Poly1305.seal(key, nonce, pt, aad: aad);
      expect(sealed.sublist(0, 16), hex('d31a8d34648e60db7b86afbc53ef7ec2'));
      expect(sealed.sublist(sealed.length - 16), hex('1ae10b594f09e26a7e902ecbd0600691'));
      expect(ChaCha20Poly1305.open(key, nonce, sealed, aad: aad), pt);
    });

    test('matches package:cryptography for many lengths', () async {
      final reference = Chacha20.poly1305Aead();
      for (final length in [0, 1, 15, 16, 17, 63, 64, 65, 255, 1000, 4097, 65536, 262144 + 3]) {
        final key = Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + length) & 0xFF));
        final nonce = Uint8List.fromList(List<int>.generate(12, (i) => (i * 3 + length) & 0xFF));
        final pt = Uint8List.fromList(List<int>.generate(length, (i) => (i * 31 + 11) & 0xFF));
        final box = await reference.encrypt(pt, secretKey: SecretKey(key), nonce: nonce);
        final ours = ChaCha20Poly1305.seal(key, nonce, pt);
        expect(ours.sublist(0, length), box.cipherText, reason: 'ciphertext, length $length');
        expect(ours.sublist(length), box.mac.bytes, reason: 'tag, length $length');
        expect(ChaCha20Poly1305.open(key, nonce, ours), pt);
      }
    });

    test('unaligned input views work', () {
      final key = Uint8List(32);
      final nonce = Uint8List(12);
      final backing = Uint8List(5000);
      final view = Uint8List.sublistView(backing, 3, 4003);
      final sealed = ChaCha20Poly1305.seal(key, nonce, view);
      expect(ChaCha20Poly1305.open(key, nonce, Uint8List(10)), isNull);
      expect(ChaCha20Poly1305.open(key, nonce, sealed), view);
    });
  });

  group('AEAD engines', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final big = Uint8List.fromList(List<int>.generate(300 * 1024, (i) => (i * 13) & 0xFF));

    test('isolate pool and inline produce identical frames', () async {
      final pool = IsolateAead(workers: 2);
      addTearDown(pool.dispose);
      final inline = CipherAead();
      final a = await pool.seal(key, 42, big);
      final b = await inline.seal(key, 42, big);
      expect(a, b);
      expect(await pool.open(key, 42, a), big);
    });

    test('tampered, replayed or reordered frames are rejected', () async {
      final pool = IsolateAead(workers: 2);
      addTearDown(pool.dispose);
      final sealed = await pool.seal(key, 7, big);
      final flipped = Uint8List.fromList(sealed)..[100] ^= 1;
      await expectLater(pool.open(key, 7, flipped), throwsA(isA<WraithException>()));
      await expectLater(pool.open(key, 8, sealed), throwsA(isA<WraithException>()));
    });
  });

  test('pairing links round-trip and reject garbage', () {
    final info = PairingInfo(
      name: 'Seif-Pi',
      fingerprint: 'A' * 32,
      addresses: [InternetAddress('192.168.1.5'), InternetAddress('10.0.0.2')],
      port: 47824,
      token: newPairingToken(),
    );
    final back = PairingInfo.tryParse(info.toUri())!;
    expect(back.fingerprint, info.fingerprint);
    expect(back.addresses.map((a) => a.address), ['192.168.1.5', '10.0.0.2']);
    expect(back.token, info.token);
    expect(PairingInfo.tryParse('https://evil.example/pair?fp=x'), isNull);
    expect(PairingInfo.tryParse('sudosend://pair?v=1&fp=XYZ&a=1.2.3.4&p=1'), isNull);
  });

  test('QR pairing: trusted on both sides, accepted without a prompt', () async {
    var prompted = false;
    final t = await _pair(onIncoming: (r) {
      prompted = true;
      r.respond(false);
    });
    final token = t.receiver.createPairingToken();
    final f = File(p.join(t.tmp.path, 'a.txt'))..writeAsStringSync('paired');
    final job = await t.sender.send(t.peer, [FileEntry(name: 'a.txt', size: 6, path: f.path)], pairToken: token);
    expect(job.status, TransferStatus.done);
    expect(prompted, isFalse);
    expect(t.bobTrust.isTrusted(t.alice.fingerprint), isTrue);
    expect(t.aliceTrust.isTrusted(t.bob.fingerprint), isTrue);

    // One-time: a second use of the same token falls back to a prompt.
    final again = await t.sender.send(t.peer, [FileEntry(name: 'a.txt', size: 6, path: f.path)], pairToken: token);
    expect(prompted, isTrue);
    expect(again.status, TransferStatus.declined);
  });

  test('a wrong pairing token is not trusted', () async {
    var prompted = false;
    final t = await _pair(onIncoming: (r) {
      prompted = true;
      r.respond(false);
    });
    t.receiver.createPairingToken();
    final f = File(p.join(t.tmp.path, 'a.txt'))..writeAsStringSync('x');
    final job = await t.sender.send(t.peer, [FileEntry(name: 'a.txt', size: 1, path: f.path)], pairToken: newPairingToken());
    expect(prompted, isTrue);
    expect(job.status, TransferStatus.declined);
    expect(t.bobTrust.isTrusted(t.alice.fingerprint), isFalse);
  });

  test('blocked devices are declined without a prompt', () async {
    var prompts = 0;
    final t = await _pair(onIncoming: (r) {
      prompts++;
      r.respond(false, block: true);
    });
    final f = File(p.join(t.tmp.path, 'a.txt'))..writeAsStringSync('x');
    final entry = [FileEntry(name: 'a.txt', size: 1, path: f.path)];
    expect((await t.sender.send(t.peer, entry)).status, TransferStatus.declined);
    expect(t.bobTrust.isBlocked(t.alice.fingerprint), isTrue);
    expect((await t.sender.send(t.peer, entry)).status, TransferStatus.declined);
    expect(prompts, 1);
  });

  test('connection flood from one address is cut off', () async {
    final t = await _pair(limits: const ConnectionLimits(maxPerMinutePerIp: 5));
    final sockets = <Socket>[];
    for (var i = 0; i < 12; i++) {
      sockets.add(await Socket.connect(InternetAddress.loopbackIPv4, t.receiver.port));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final s in sockets) {
      s.destroy();
    }
    expect(t.receiver.rejectedConnections, greaterThanOrEqualTo(7));
  });

  test('only one prompt per address at a time', () async {
    final requests = <IncomingRequest>[];
    final t = await _pair(onIncoming: requests.add);
    final f = File(p.join(t.tmp.path, 'a.txt'))..writeAsStringSync('x');
    final entry = [FileEntry(name: 'a.txt', size: 1, path: f.path)];
    final first = t.sender.send(t.peer, entry);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final second = await t.sender.send(t.peer, entry);
    expect(second.status, TransferStatus.declined);
    expect(requests, hasLength(1));
    requests.single.respond(true);
    expect((await first).status, TransferStatus.done);
  });
}

class _Pair {
  _Pair(this.tmp, this.alice, this.bob, this.inbox, this.receiver, this.sender, this.peer, this.aliceTrust,
      this.bobTrust);
  final Directory tmp;
  final DeviceIdentity alice;
  final DeviceIdentity bob;
  final Directory inbox;
  final TransferEngine receiver;
  final TransferEngine sender;
  final Peer peer;
  final TrustStore aliceTrust;
  final TrustStore bobTrust;
}

Future<_Pair> _pair({
  void Function(IncomingRequest r)? onIncoming,
  ConnectionLimits limits = const ConnectionLimits(),
}) async {
  final tmp = await Directory.systemTemp.createTemp('sudosend_test_');
  addTearDown(() => tmp.delete(recursive: true));
  final alice = await DeviceIdentity.loadOrCreate(Directory(p.join(tmp.path, 'alice')));
  final bob = await DeviceIdentity.loadOrCreate(Directory(p.join(tmp.path, 'bob')));
  final inbox = await Directory(p.join(tmp.path, 'inbox')).create();
  final bobTrust = await TrustStore.load(Directory(p.join(tmp.path, 'bob')));
  final aliceTrust = await TrustStore.load(Directory(p.join(tmp.path, 'alice')));
  final receiver = TransferEngine(
    identity: bob,
    trust: bobTrust,
    limits: limits,
    saveDir: () async => inbox,
    onIncoming: onIncoming ?? (r) => r.respond(true),
    onJob: (_) {},
    basePort: 0,
  );
  await receiver.start();
  addTearDown(receiver.stop);
  final sender = TransferEngine(
    identity: alice,
    trust: aliceTrust,
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
  return _Pair(tmp, alice, bob, inbox, receiver, sender, peer, aliceTrust, bobTrust);
}
