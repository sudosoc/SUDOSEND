import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wraith_core/identity.dart';
import 'package:cryptography/cryptography.dart';
import 'package:wraith_core/aead.dart';
import 'package:wraith_core/chacha_poly.dart';
import 'package:wraith_core/inspect.dart';
import 'package:wraith_core/journal.dart';
import 'package:wraith_core/metadata.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/organize.dart';
import 'package:wraith_core/pairing.dart';
import 'package:wraith_core/receipt.dart';
import 'package:wraith_core/risk.dart';
import 'package:wraith_core/sync.dart';
import 'package:wraith_core/web_share.dart';
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

  test('signed delivery receipts: verified by sender, exportable, tamper-evident', () async {
    TransferJob? received;
    final t = await _pair();
    final tmpRx = TransferEngine(
      identity: t.bob,
      trust: t.bobTrust,
      saveDir: () async => t.inbox,
      onIncoming: (r) => r.respond(true),
      onJob: (j) => received = j,
      basePort: 0,
    );
    await tmpRx.start();
    addTearDown(tmpRx.stop);
    final f = File(p.join(t.tmp.path, 'evidence.bin'))..writeAsBytesSync(List<int>.generate(70000, (i) => i & 0xFF));
    final peer = Peer(
      id: t.bob.fingerprint,
      name: 'bob',
      platform: 'linux',
      address: InternetAddress.loopbackIPv4,
      port: tmpRx.port,
      lastSeen: DateTime.now(),
    );
    final job = await t.sender.send(peer, [FileEntry(name: 'evidence.bin', size: 70000, path: f.path)]);
    expect(job.status, TransferStatus.done, reason: job.error);
    final receipt = job.receipt!;
    expect(await receipt.verifySignature(), isTrue);
    expect(receipt.signerFingerprint, t.bob.fingerprint);
    expect((receipt.data['sender'] as Map)['fingerprint'], t.alice.fingerprint);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received!.receipt!.body, receipt.body);

    final exported = DeliveryReceipt.parse(receipt.toPrettyJson());
    expect(await exported.verifySignature(), isTrue);

    final forged = DeliveryReceipt(
      body: receipt.body.replaceFirst('"total_bytes":70000', '"total_bytes":70001'),
      signature: receipt.signature,
      signerKey: receipt.signerKey,
    );
    expect(await forged.verifySignature(), isFalse);
  });

  test('per-sender folders', () async {
    final t = await _pair();
    final rx = TransferEngine(
      identity: t.bob,
      trust: t.bobTrust,
      saveDir: () async => t.inbox,
      saveDirFor: (name, fp) async => Directory(p.join(t.inbox.path, 'from-${fp.substring(0, 4)}')),
      onIncoming: (r) => r.respond(true),
      onJob: (_) {},
      basePort: 0,
    );
    await rx.start();
    addTearDown(rx.stop);
    final f = File(p.join(t.tmp.path, 'x.txt'))..writeAsStringSync('hi');
    final job = await t.sender.send(
      Peer(id: t.bob.fingerprint, name: 'b', platform: 'x', address: InternetAddress.loopbackIPv4, port: rx.port, lastSeen: DateTime.now()),
      [FileEntry(name: 'x.txt', size: 2, path: f.path)],
    );
    expect(job.status, TransferStatus.done);
    expect(File(p.join(t.inbox.path, 'from-${t.alice.fingerprint.substring(0, 4)}', 'x.txt')).readAsStringSync(), 'hi');
  });

  test('browser share: page, download, upload, wrong token', () async {
    final tmp = await Directory.systemTemp.createTemp('sudosend_web_');
    addTearDown(() => tmp.delete(recursive: true));
    final inbox = await Directory(p.join(tmp.path, 'inbox')).create();
    final src = File(p.join(tmp.path, 'report.pdf'))..writeAsBytesSync(List<int>.generate(5000, (i) => i & 0xFF));
    final events = <WebShareEvent>[];
    final share = WebShare(
      files: [FileEntry(name: 'report.pdf', size: 5000, path: src.path)],
      text: 'hello <b>',
      allowUpload: true,
      saveDir: () async => inbox,
      onEvent: events.add,
      basePort: 0,
    );
    await share.start();
    addTearDown(share.stop);
    final base = share.urls([InternetAddress.loopbackIPv4]).single;
    final client = HttpClient();
    addTearDown(client.close);

    Future<(int, List<int>)> get(String url) async {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      return (res.statusCode, await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)));
    }

    final (pageStatus, page) = await get(base);
    expect(pageStatus, 200);
    final html = String.fromCharCodes(page);
    expect(html, contains('report.pdf'));
    expect(html, isNot(contains('hello <b>')), reason: 'text must be HTML-escaped');

    final (fileStatus, bytes) = await get('${base}f/0');
    expect(fileStatus, 200);
    expect(bytes, src.readAsBytesSync());

    final (badStatus, _) = await get(base.replaceFirst(share.token, newPairingToken()));
    expect(badStatus, 404);

    final req = await client.postUrl(Uri.parse('${base}u?name=${Uri.encodeComponent('../../evil.txt')}'));
    req.add('uploaded!'.codeUnits);
    final res = await req.close();
    await res.drain<void>();
    expect(res.statusCode, 200);
    expect(File(p.join(inbox.path, 'evil.txt')).readAsStringSync(), 'uploaded!');
    expect(File(p.join(tmp.path, 'evil.txt')).existsSync(), isFalse);
    expect(events.map((e) => e.kind), containsAll(['visit', 'download', 'upload']));
  });

  test('clipboard pushes are flagged on both sides', () async {
    IncomingRequest? seen;
    final t = await _pair(onIncoming: (r) {
      seen = r;
      r.respond(true);
    });
    final job = await t.sender.send(t.peer, const [], text: 'copied!', clipboard: true);
    expect(job.status, TransferStatus.done);
    expect(job.clipboard, isTrue);
    expect(seen!.clipboard, isTrue);
  });

  test('ring requests reach the receiver flagged, with no files', () async {
    IncomingRequest? seen;
    final t = await _pair(onIncoming: (r) {
      seen = r;
      r.respond(true);
    });
    final job = await t.sender.send(t.peer, const [], ring: true);
    expect(job.status, TransferStatus.done, reason: job.error);
    expect(seen!.ring, isTrue);
  });

  test('upload speed cap is respected', () async {
    final t = await _pair();
    final f = File(p.join(t.tmp.path, 'slow.bin'))..writeAsBytesSync(List<int>.filled(600 * 1024, 1));
    TransferEngine.maxBytesPerSecond = 1024 * 1024; // 1 MiB/s → ≥ ~0.5 s
    addTearDown(() => TransferEngine.maxBytesPerSecond = 0);
    final sw = Stopwatch()..start();
    final job = await t.sender.send(t.peer, [FileEntry(name: 'slow.bin', size: 600 * 1024, path: f.path)]);
    expect(job.status, TransferStatus.done);
    expect(sw.elapsedMilliseconds, greaterThan(400));
  });

  test('browser share: PIN gate and self-destruct after N downloads', () async {
    final tmp = await Directory.systemTemp.createTemp('sudosend_web_pin_');
    addTearDown(() => tmp.delete(recursive: true));
    final src = File(p.join(tmp.path, 'a.txt'))..writeAsStringSync('secret');
    var stopped = false;
    final share = WebShare(
      files: [FileEntry(name: 'a.txt', size: 6, path: src.path)],
      saveDir: () async => tmp,
      pin: '4821',
      maxDownloads: 1,
      onStopped: () => stopped = true,
      basePort: 0,
    );
    await share.start();
    addTearDown(share.stop);
    final base = share.urls([InternetAddress.loopbackIPv4]).single;
    final client = HttpClient();
    addTearDown(client.close);

    var res = await (await client.getUrl(Uri.parse('${base}f/0'))).close();
    await res.drain<void>();
    expect(res.statusCode, 403, reason: 'files need the PIN');

    var req = await client.postUrl(Uri.parse('${base}pin'));
    req.followRedirects = false;
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    req.write('pin=0000');
    res = await req.close();
    await res.drain<void>();
    expect(res.statusCode, 403, reason: 'wrong PIN');

    req = await client.postUrl(Uri.parse('${base}pin'));
    req.followRedirects = false;
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    req.write('pin=4821');
    res = await req.close();
    await res.drain<void>();
    expect(res.statusCode, 303);
    final cookie = res.cookies.single;

    final get = await client.getUrl(Uri.parse('${base}f/0'));
    get.cookies.add(cookie);
    res = await get.close();
    expect(String.fromCharCodes(await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b))), 'secret');
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(stopped, isTrue, reason: 'one-download link must self-destruct');
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

  test('smart compression: text shrinks on the wire, media is left alone, data is exact', () async {
    final t = await _pair();
    final text = List<int>.generate(3 * 1024 * 1024 + 11, (i) => 'SUDOSEND log line $i\n'.codeUnitAt(i % 20));
    final rng = Random(7);
    final noise = List<int>.generate(1024 * 1024, (_) => rng.nextInt(256));
    final a = File(p.join(t.tmp.path, 'server.log'))..writeAsBytesSync(text);
    final b = File(p.join(t.tmp.path, 'noise.bin'))..writeAsBytesSync(noise);
    final c = File(p.join(t.tmp.path, 'photo.jpg'))..writeAsBytesSync(text.sublist(0, 200000));
    final job = await t.sender.send(t.peer, [
      FileEntry(name: 'server.log', size: text.length, path: a.path),
      FileEntry(name: 'noise.bin', size: noise.length, path: b.path),
      FileEntry(name: 'photo.jpg', size: 200000, path: c.path),
    ]);
    expect(job.status, TransferStatus.done, reason: job.error);
    expect(job.compressedSaved, greaterThan(text.length ~/ 2));
    expect(File(p.join(t.inbox.path, 'server.log')).readAsBytesSync(), text);
    expect(File(p.join(t.inbox.path, 'noise.bin')).readAsBytesSync(), noise);
    expect(File(p.join(t.inbox.path, 'photo.jpg')).readAsBytesSync(), text.sublist(0, 200000));
  });

  test('compression can be switched off', () async {
    final t = await _pair();
    TransferEngine.compression = false;
    addTearDown(() => TransferEngine.compression = true);
    final f = File(p.join(t.tmp.path, 'zeros.bin'))..writeAsBytesSync(List<int>.filled(500000, 0));
    final job = await t.sender.send(t.peer, [FileEntry(name: 'zeros.bin', size: 500000, path: f.path)]);
    expect(job.status, TransferStatus.done);
    expect(job.compressedSaved, 0);
  });

  test('decompression bombs are refused', () {
    final bomb = Uint8List.fromList(ZLibEncoder(raw: true).convert(List<int>.filled(10 * 1024 * 1024, 0)));
    expect(() => inflateBounded(bomb, 1024 * 1024), throwsA(isA<WraithException>()));
    final ok = Uint8List.fromList(ZLibEncoder(raw: true).convert(List<int>.filled(1000, 5)));
    expect(inflateBounded(ok, 1000), List<int>.filled(1000, 5));
    expect(worthCompressing('a.MP4'), isFalse);
    expect(worthCompressing('notes.txt'), isTrue);
    expect(worthCompressing('Makefile'), isTrue);
  });

  test('speed test works between trusted devices only', () async {
    final t = await _pair(autoAccept: (r) => r.speedTest && r.trusted);
    await expectLater(t.sender.speedTest(t.peer, duration: const Duration(milliseconds: 300)),
        throwsA(isA<WraithException>()));
    await t.bobTrust.add(t.alice.fingerprint, t.alice.name);
    final rate = await t.sender.speedTest(t.peer, duration: const Duration(milliseconds: 600));
    expect(rate, greaterThan(1024 * 1024)); // loopback: far above 1 MB/s
    expect(t.inbox.listSync(), isEmpty, reason: 'speed test writes nothing');
  });

  test('chat messages and previews reach the receiver', () async {
    IncomingRequest? seen;
    final t = await _pair(onIncoming: (r) {
      seen = r;
      r.respond(true);
    });
    final job = await t.sender.send(t.peer, const [], text: 'أهلا 👋', chat: true);
    expect(job.status, TransferStatus.done);
    expect(seen!.chat, isTrue);

    final f = File(p.join(t.tmp.path, 'pic.png'))..writeAsBytesSync(List<int>.filled(10, 1));
    final thumb = Uint8List.fromList(List<int>.generate(300, (i) => i & 0xFF));
    await t.sender.send(t.peer, [FileEntry(name: 'pic.png', size: 10, path: f.path)], previews: {0: thumb, 5: thumb});
    expect(seen!.chat, isFalse);
    expect(seen!.previews.keys, [0], reason: 'out-of-range previews are dropped');
    expect(seen!.previews[0], thumb);
  });

  test('manifest planning: newer or missing files are pushed', () {
    const local = [ManifestEntry('a', 1, 10000), ManifestEntry('b', 1, 10000), ManifestEntry('c', 1, 10000)];
    const remote = [ManifestEntry('a', 1, 9000), ManifestEntry('b', 1, 5000)];
    expect(planPush(local, remote).map((e) => e.path), ['b', 'c']);
    final round = decodeManifest(encodeManifest(local));
    expect(round.map((e) => '${e.path}${e.size}${e.mtime}'), local.map((e) => '${e.path}${e.size}${e.mtime}'));
  });

  test('folder sync: invite, manifest, overwrite with archive, mtime kept', () async {
    var prompted = 0;
    final t = await _pair(onIncoming: (r) {
      prompted++;
      r.respond(r.syncInvite != null);
    });
    final bobFolder = await Directory(p.join(t.tmp.path, 'bob-sync')).create();
    final aliceFolder = await Directory(p.join(t.tmp.path, 'alice-sync')).create();
    t.receiver.syncFolder = (id, fp) => id == 'S1' && fp == t.alice.fingerprint ? bobFolder : null;

    // Untrusted: sync offers and manifests are refused.
    await expectLater(t.sender.fetchManifest(t.peer, 'S1'), throwsA(isA<WraithException>()));
    expect(await t.sender.sendSyncInvite(t.peer, 'S1', 'Projects'), isTrue);
    expect(prompted, 1);
    await t.bobTrust.add(t.alice.fingerprint, t.alice.name);

    File(p.join(bobFolder.path, 'notes.txt')).writeAsStringSync('old');
    final when = DateTime.now().add(const Duration(minutes: 5));
    final src = File(p.join(aliceFolder.path, 'notes.txt'))..writeAsStringSync('new version');
    await src.setLastModified(when);
    File(p.join(aliceFolder.path, 'sub', 'x.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');

    final remote = await t.sender.fetchManifest(t.peer, 'S1');
    expect(remote.map((e) => e.path), ['notes.txt']);
    final local = await buildManifest(aliceFolder);
    final push = planPush(local, remote);
    expect(push.map((e) => e.path).toSet(), {'notes.txt', 'sub/x.txt'});
    final job = await t.sender.send(
      t.peer,
      [for (final e in push) FileEntry(name: e.path, size: e.size, path: p.join(aliceFolder.path, e.path), mtime: e.mtime)],
      syncId: 'S1',
    );
    expect(job.status, TransferStatus.done, reason: job.error);
    expect(prompted, 1, reason: 'sync pushes never prompt');
    final updated = File(p.join(bobFolder.path, 'notes.txt'));
    expect(updated.readAsStringSync(), 'new version');
    expect((updated.lastModifiedSync().millisecondsSinceEpoch - when.millisecondsSinceEpoch).abs(), lessThan(2000));
    expect(File(p.join(bobFolder.path, 'sub', 'x.txt')).readAsStringSync(), 'x');
    final archived = Directory(p.join(bobFolder.path, kSyncArchive)).listSync(recursive: true).whereType<File>();
    expect(archived.single.readAsStringSync(), 'old');

    // Now both sides agree: nothing left to push either way.
    final after = await t.sender.fetchManifest(t.peer, 'S1');
    expect(planPush(await buildManifest(aliceFolder), after), isEmpty);
    expect(planPush(after, await buildManifest(aliceFolder)), isEmpty);
  });

  test('categorize sorts by extension, unknown goes to Other Files', () {
    expect(categorize('Report.PDF'), FileCategory.documents);
    expect(categorize('IMG_0001.HEIC'), FileCategory.pictures);
    expect(categorize('clip.mkv'), FileCategory.videos);
    expect(categorize('voice.opus'), FileCategory.audio);
    expect(categorize('backup.tar.gz'), FileCategory.archives);
    expect(categorize('app-release.apk'), FileCategory.applications);
    expect(categorize('main.dart'), FileCategory.code);
    expect(categorize('Dockerfile'), FileCategory.code);
    expect(categorize('mystery.xyz123'), FileCategory.other);
    expect(categorize('noextension'), FileCategory.other);
    expect(categorize('.hidden'), FileCategory.other);
  });

  test('organize rules build device/type/date paths; folders stay whole', () {
    final day = DateTime(2026, 11, 2, 23, 59);
    const rules = OrganizeRules();
    expect(rules.place('Galaxy A52', ['photo.jpg'], day), ['Galaxy A52', 'Pictures', '2026-11-02', 'photo.jpg']);
    expect(rules.place('Laptop', ['Album', '2026', 'a.txt'], day), ['Laptop', 'Folders', '2026-11-02', 'Album', '2026', 'a.txt']);
    expect(rules.place('../evil', ['x.pdf'], day).first, isNot(contains('/')));
    expect(const OrganizeRules(byDevice: false, byDate: false).place('P', ['a.zip'], day), ['Archives', 'a.zip']);
  });

  test('received files land in device/category/date folders', () async {
    final t = await _pair();
    t.receiver.placeFile = (name, fp, segs) => const OrganizeRules().place('Android', segs, DateTime(2026, 11, 2));
    final a = File(p.join(t.tmp.path, 'report.pdf'))..writeAsStringSync('pdf');
    final b = File(p.join(t.tmp.path, 'photo.jpg'))..writeAsStringSync('jpg');
    final c = File(p.join(t.tmp.path, 'thing.weird'))..writeAsStringSync('??');
    final d = File(p.join(t.tmp.path, 'a.txt'))..writeAsStringSync('in a folder');
    final job = await t.sender.send(t.peer, [
      FileEntry(name: 'report.pdf', size: 3, path: a.path),
      FileEntry(name: 'photo.jpg', size: 3, path: b.path),
      FileEntry(name: 'thing.weird', size: 2, path: c.path),
      FileEntry(name: 'Project/docs/a.txt', size: 11, path: d.path),
    ]);
    expect(job.status, TransferStatus.done, reason: job.error);
    String at(List<String> parts) => p.joinAll([t.inbox.path, 'Android', ...parts]);
    expect(File(at(['Documents', '2026-11-02', 'report.pdf'])).readAsStringSync(), 'pdf');
    expect(File(at(['Pictures', '2026-11-02', 'photo.jpg'])).readAsStringSync(), 'jpg');
    expect(File(at(['Other Files', '2026-11-02', 'thing.weird'])).readAsStringSync(), '??');
    expect(File(at(['Folders', '2026-11-02', 'Project', 'docs', 'a.txt'])).readAsStringSync(), 'in a folder');
  });

  test('risky files: double extensions, disguised programs, scripts', () {
    expect(assessRisk('holiday.jpg').level, RiskLevel.none);
    expect(assessRisk('invoice.pdf.exe').reason, 'double-extension');
    expect(assessRisk('setup.exe').level, RiskLevel.caution);
    expect(assessRisk('run.ps1').reason, 'script');
    expect(assessRisk('budget.xlsm').reason, 'macro');
    expect(assessRisk('photo\u202Egpj.exe').level, RiskLevel.danger);
    expect(assessRisk('cv.pdf', [0x4D, 0x5A, 0x90, 0x00]).reason, 'disguised');
    expect(assessRisk('notes.txt', '#!/bin/sh'.codeUnits).reason, 'disguised-script');
    expect(assessRisk('cv.pdf', '%PDF-1.7'.codeUnits).level, RiskLevel.none);
  });

  group('metadata explorer', () {
    test('JPEG EXIF: camera and GPS', () {
      final t = BytesBuilder();
      void u16(int v) => t.add([v >> 8, v & 0xFF]);
      void u32(int v) => t.add([v >> 24, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
      t.add([0x4D, 0x4D]);
      u16(42);
      u32(8);
      u16(2); // IFD0
      u16(0x010F); u16(2); u32(6); u32(38);
      u16(0x8825); u16(4); u32(1); u32(44);
      u32(0);
      t.add('Canon\u0000'.codeUnits); // 38..43
      u16(4); // GPS IFD at 44
      u16(1); u16(2); u32(2); t.add([0x4E, 0, 0, 0]);
      u16(2); u16(5); u32(3); u32(98);
      u16(3); u16(2); u32(2); t.add([0x45, 0, 0, 0]);
      u16(4); u16(5); u32(3); u32(122);
      u32(0); // 94..97
      for (final v in [30, 1, 2, 1, 40, 1, 31, 1, 14, 1, 852, 100]) {
        u32(v);
      }
      final tiff = t.takeBytes();
      final app1 = [...'Exif'.codeUnits, 0, 0, ...tiff];
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8,
        0xFF, 0xE1, (app1.length + 2) >> 8, (app1.length + 2) & 0xFF, ...app1,
        0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x01, 0xE0, 0x02, 0x80, 0x03, 0x01, 0x22, 0x00, //
        0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xD9,
      ]);
      final m = inspectBytes(jpeg);
      expect(m.format, 'JPEG');
      expect(m['make'], 'Canon');
      expect(m['width'], '640');
      expect(m['height'], '480');
      expect(m.latitude, closeTo(30.044444, 1e-5));
      expect(m.longitude, closeTo(31.2357, 1e-5));
    });

    test('PDF info dictionary and risky features', () {
      final pdf = Uint8List.fromList(
          '%PDF-1.7\n1 0 obj << /Title (Quarterly \\(Q3\\) report) /Author (Seif) /CreationDate (D:20261102120000) >> endobj\n/OpenAction << /S /JavaScript /JS (app.alert(1)) >>\ntrailer << /Encrypt 5 0 R >>'
              .codeUnits);
      final m = inspectBytes(pdf);
      expect(m['pdfVersion'], '1.7');
      expect(m['title'], 'Quarterly (Q3) report');
      expect(m['author'], 'Seif');
      expect(m['created'], '2026-11-02 12:00');
      expect(m['encrypted'], 'yes');
      expect(m['javascript'], 'yes');
    });

    test('Office document properties and macros (zip)', () async {
      final dir = await Directory.systemTemp.createTemp('sudosend_meta_');
      addTearDown(() => dir.delete(recursive: true));
      List<int> le16(int v) => [v & 0xFF, v >> 8];
      List<int> le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
      final files = {
        'docProps/core.xml':
            '<cp:coreProperties><dc:title>Budget</dc:title><dc:creator>Seif &amp; Co</dc:creator><dcterms:created xsi:type="x">2026-11-01T10:00:00Z</dcterms:created></cp:coreProperties>',
        'docProps/app.xml': '<Properties><Application>Microsoft Excel</Application><Company>SUDOSOC</Company></Properties>',
        'xl/vbaProject.bin': 'macro',
      };
      final out = BytesBuilder();
      final central = BytesBuilder();
      for (final e in files.entries) {
        final name = e.key.codeUnits, data = e.value.codeUnits;
        final offset = out.length;
        out
          ..add(le32(0x04034b50))
          ..add(le16(20))
          ..add(le16(0))
          ..add(le16(0)) // stored
          ..add(le16(0))
          ..add(le16(0))
          ..add(le32(0))
          ..add(le32(data.length))
          ..add(le32(data.length))
          ..add(le16(name.length))
          ..add(le16(0))
          ..add(name)
          ..add(data);
        central
          ..add(le32(0x02014b50))
          ..add(le16(20))
          ..add(le16(20))
          ..add(le16(0))
          ..add(le16(0))
          ..add(le16(0))
          ..add(le16(0))
          ..add(le32(0))
          ..add(le32(data.length))
          ..add(le32(data.length))
          ..add(le16(name.length))
          ..add(le16(0))
          ..add(le16(0))
          ..add(le16(0))
          ..add(le16(0))
          ..add(le32(0))
          ..add(le32(offset))
          ..add(name);
      }
      final cdOffset = out.length;
      final cd = central.takeBytes();
      out
        ..add(cd)
        ..add(le32(0x06054b50))
        ..add(le16(0))
        ..add(le16(0))
        ..add(le16(files.length))
        ..add(le16(files.length))
        ..add(le32(cd.length))
        ..add(le32(cdOffset))
        ..add(le16(0));
      final f = File(p.join(dir.path, 'budget.xlsm'))..writeAsBytesSync(out.takeBytes());
      final m = await inspectFile(f.path);
      expect(m['title'], 'Budget');
      expect(m['author'], 'Seif & Co');
      expect(m['application'], 'Microsoft Excel');
      expect(m['company'], 'SUDOSOC');
      expect(m['created'], '2026-11-01T10:00:00Z');
      expect(m['macros'], 'yes');
    });

    test('MP4 creation date and duration, MP3 tags', () async {
      final dir = await Directory.systemTemp.createTemp('sudosend_meta_');
      addTearDown(() => dir.delete(recursive: true));
      List<int> be32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
      final created = DateTime.utc(2026, 1, 2).difference(DateTime.utc(1904)).inSeconds;
      final mvhd = [0, 0, 0, 0, ...be32(created), ...be32(created), ...be32(1000), ...be32(65000), ...List<int>.filled(80, 0)];
      final mvhdBox = [...be32(mvhd.length + 8), ...'mvhd'.codeUnits, ...mvhd];
      final moov = [...be32(mvhdBox.length + 8), ...'moov'.codeUnits, ...mvhdBox];
      final ftyp = [...be32(16), ...'ftyp'.codeUnits, ...'isom'.codeUnits, 0, 0, 0, 0];
      final mp4 = File(p.join(dir.path, 'clip.mp4'))..writeAsBytesSync([...ftyp, ...moov]);
      final m = await inspectFile(mp4.path);
      expect(m['duration'], '01:05');
      expect(m['created'], startsWith('2026-01-02'));
      expect(m['brand'], 'isom');

      final frame = [0, ...'Hello'.codeUnits];
      final id3 = [
        ...'ID3'.codeUnits, 3, 0, 0, 0, 0, 0, 10 + frame.length, //
        ...'TIT2'.codeUnits, ...be32(frame.length), 0, 0, ...frame,
      ];
      expect(inspectBytes(Uint8List.fromList(id3))['title'], 'Hello');
    });

    test('hostile input never throws', () {
      for (final junk in [
        [0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00],
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0x49, 0x48],
        '%PDF-'.codeUnits,
        'ID3\u0004\u0000\u0000\u007f\u007f\u007f\u007f'.codeUnits,
      ]) {
        expect(() => inspectBytes(Uint8List.fromList(junk)), returnsNormally);
      }
    });
  });

  test('smart recovery: an interrupted replace is rolled back', () async {
    final dir = await Directory.systemTemp.createTemp('sudosend_journal_');
    addTearDown(() => dir.delete(recursive: true));
    final j = Journal(File(p.join(dir.path, 'journal.jsonl')));
    final dest = File(p.join(dir.path, 'notes.txt'));
    final archived = File(p.join(dir.path, 'archive', 'notes.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('old copy');
    // Crash: the old file was archived but the new one never arrived.
    j.begin('replace', {'dest': dest.path, 'archived': archived.path});
    final done = j.begin('replace', {'dest': '/nope', 'archived': '/nope2'});
    j.end(done);
    expect(j.pending(), hasLength(1));
    final r = await recoverJournal(j);
    expect(dest.readAsStringSync(), 'old copy');
    expect(r.repaired, hasLength(1));
    expect(j.pending(), isEmpty);

    // Interrupted cross-volume move: the partial copy is removed, the original kept.
    final from = File(p.join(dir.path, 'big.bin'))..writeAsBytesSync(List<int>.filled(1000, 1));
    final to = File(p.join(dir.path, 'trash', 'big.bin'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(10, 1));
    j.begin('move', {'from': from.path, 'to': to.path});
    await recoverJournal(j);
    expect(from.existsSync(), isTrue);
    expect(to.existsSync(), isFalse);
  });

  test('search across devices: trusted only, no paths, fetch by hash', () async {
    final t = await _pair();
    String? fetched;
    t.receiver.onSearch = (fp, q) => [
          {'n': 'report.pdf', 's': 1234, 'h': 'a' * 64, 'q': q['q']},
        ];
    t.receiver.onFetch = (fp, sha) {
      fetched = sha;
      return true;
    };
    expect(await t.sender.searchRemote(t.peer, {'q': 'rep'}), isNull, reason: 'untrusted devices get nothing');
    expect(await t.sender.requestFetch(t.peer, 'a' * 64), isFalse);
    await t.bobTrust.add(t.alice.fingerprint, t.alice.name);
    final hits = await t.sender.searchRemote(t.peer, {'q': 'rep'});
    expect(hits!.single['n'], 'report.pdf');
    expect(hits.single['q'], 'rep');
    expect(await t.sender.requestFetch(t.peer, 'not-a-hash'), isFalse);
    expect(await t.sender.requestFetch(t.peer, 'b' * 64), isTrue);
    expect(fetched, 'b' * 64);
  });

  group('metadata scrubbing', () {
    // Builds a JPEG header: SOI, optional APP0, an EXIF APP1 (IFD0 with
    // Orientation and a GPS pointer, GPS IFD with a latitude), XMP, then a
    // stand-in scan segment.
    Uint8List jpeg({required bool little}) {
      final t = BytesBuilder();
      void u16(int v) => t.add(little ? [v & 0xFF, v >> 8] : [v >> 8, v & 0xFF]);
      void u32(int v) => t.add(little
          ? [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24]
          : [v >> 24, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
      t.add(little ? [0x49, 0x49] : [0x4D, 0x4D]);
      u16(42);
      u32(8);
      // IFD0 at 8: 2 entries
      u16(2);
      u16(0x0112); u16(3); u32(1); u16(6); u16(0); // Orientation = 6
      u16(0x8825); u16(4); u32(1); u32(38); // GPS IFD at 38
      u32(0); // next IFD
      // GPS IFD at 38: 1 entry, GPSLatitude (RATIONAL x3 = 24 bytes) at 56
      u16(1);
      u16(0x0002); u16(5); u32(3); u32(56);
      u32(0);
      // value at 56
      for (final v in [30, 1, 7, 1, 5, 1]) {
        u32(v);
      }
      final tiff = t.takeBytes();
      final app1 = [...'Exif'.codeUnits, 0, 0, ...tiff];
      final xmp = [...'http://ns.adobe.com/xap/1.0/'.codeUnits, 0, ...'<x:xmpmeta>GPS</x:xmpmeta>'.codeUnits];
      final out = BytesBuilder()
        ..add([0xFF, 0xD8])
        ..add([0xFF, 0xE0, 0x00, 0x07, 0x4A, 0x46, 0x49, 0x46, 0x00]) // APP0 "JFIF"
        ..add([0xFF, 0xE1, (app1.length + 2) >> 8, (app1.length + 2) & 0xFF, ...app1])
        ..add([0xFF, 0xE1, (xmp.length + 2) >> 8, (xmp.length + 2) & 0xFF, ...xmp])
        ..add([0xFF, 0xDA, 0x00, 0x04, 0x01, 0x02, 0x11, 0x22, 0x33, 0xFF, 0xD9]);
      return out.takeBytes();
    }

    bool containsSeq(List<int> hay, List<int> needle) {
      outer:
      for (var i = 0; i + needle.length <= hay.length; i++) {
        for (var j = 0; j < needle.length; j++) {
          if (hay[i + j] != needle[j]) continue outer;
        }
        return true;
      }
      return false;
    }

    for (final little in [true, false]) {
      test('location mode empties GPS, drops XMP, keeps orientation (${little ? 'II' : 'MM'})', () {
        final src = jpeg(little: little);
        final out = scrubMetadata(src, MetadataMode.location)!;
        final latitude = little ? [30, 0, 0, 0, 1, 0, 0, 0, 7, 0, 0, 0] : [0, 0, 0, 30, 0, 0, 0, 1, 0, 0, 0, 7];
        expect(containsSeq(src, latitude), isTrue);
        expect(containsSeq(out, latitude), isFalse, reason: 'GPS values must be gone');
        expect(containsSeq(out, 'xmpmeta'.codeUnits), isFalse);
        expect(containsSeq(out, 'Exif'.codeUnits), isTrue, reason: 'EXIF (date, orientation) stays');
        expect(out.sublist(out.length - 11), src.sublist(src.length - 11), reason: 'image data untouched');
      });
    }

    test('all mode keeps only orientation, JFIF and the image data', () {
      final src = jpeg(little: true);
      final out = scrubMetadata(src, MetadataMode.all)!;
      expect(containsSeq(out, 'xmpmeta'.codeUnits), isFalse);
      expect(containsSeq(out, [0x8825 >> 8, 0x8825 & 0xFF]), isFalse);
      // JFIF first, then the minimal EXIF with Orientation = 6 (big-endian).
      expect(out.sublist(2, 4), [0xFF, 0xE0]);
      expect(containsSeq(out, [0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x06]), isTrue);
      expect(out.sublist(out.length - 11), src.sublist(src.length - 11));
      expect(out.length, lessThan(src.length));
    });

    test('clean or unknown files are returned as null (left alone)', () {
      final clean = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xD9]);
      expect(scrubMetadata(clean, MetadataMode.all), isNull);
      expect(scrubMetadata(Uint8List.fromList('not an image'.codeUnits), MetadataMode.all), isNull);
      expect(scrubMetadata(jpeg(little: true), MetadataMode.off), isNull);
      final broken = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x7F, 0xFF, 0x00]);
      expect(scrubMetadata(broken, MetadataMode.all), isNull);
    });

    test('PNG text and eXIf chunks are removed', () {
      List<int> chunk(String type, List<int> data) => [
            (data.length >> 24) & 0xFF, (data.length >> 16) & 0xFF, (data.length >> 8) & 0xFF, data.length & 0xFF,
            ...type.codeUnits, ...data, 0, 0, 0, 0,
          ];
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        ...chunk('IHDR', List<int>.filled(13, 1)),
        ...chunk('eXIf', [1, 2, 3]),
        ...chunk('tEXt', 'Author\u0000Seif'.codeUnits),
        ...chunk('IDAT', [9, 9, 9]),
        ...chunk('IEND', const []),
      ]);
      final loc = scrubMetadata(png, MetadataMode.location)!;
      expect(containsSeq(loc, 'eXIf'.codeUnits), isFalse);
      expect(containsSeq(loc, 'tEXt'.codeUnits), isTrue);
      final all = scrubMetadata(png, MetadataMode.all)!;
      expect(containsSeq(all, 'tEXt'.codeUnits), isFalse);
      expect(containsSeq(all, 'IDAT'.codeUnits), isTrue);
    });
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
  bool Function(IncomingRequest r)? autoAccept,
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
    autoAccept: autoAccept,
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
