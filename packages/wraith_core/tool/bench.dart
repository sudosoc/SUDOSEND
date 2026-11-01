// Throughput benchmark for the Wraith core. Prints GitHub Actions notices.
//   dart run tool/bench.dart [MiB]
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:path/path.dart' as p;
import 'package:wraith_core/aead.dart';
import 'package:wraith_core/identity.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/transfer.dart';
import 'package:wraith_core/wraith.dart';

Future<double> _mbps(int bytes, Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  return bytes / (1 << 20) / (sw.elapsedMicroseconds / 1e6);
}

Future<void> main(List<String> args) async {
  final mib = args.isEmpty ? 512 : int.parse(args.first);
  final arch = '${Platform.operatingSystem}-${Platform.version.split('"').length > 1 ? Platform.version.split('"')[1] : ''}';
  final key = Uint8List(32);
  final chunk = Uint8List(kChunkSize)..fillRange(0, kChunkSize, 7);
  const n = 256; // 64 MiB of AEAD work

  final inline = CipherAead(DartChacha20.poly1305Aead());
  final inlineRate = await _mbps(n * kChunkSize, () async {
    for (var i = 0; i < n; i++) {
      await inline.seal(key, i, chunk);
    }
  });

  final pool = IsolateAead();
  await pool.seal(key, 0, chunk); // warm up workers
  final poolRate = await _mbps(n * kChunkSize, () async {
    await Future.wait([for (var i = 0; i < n; i++) pool.seal(key, i, chunk)]);
  });

  final hasher = Sha256Stream();
  final shaRate = await _mbps(n * kChunkSize, () async {
    for (var i = 0; i < n; i++) {
      hasher.add(chunk);
    }
    hasher.close();
  });

  // End-to-end loopback transfer through the real engine.
  final tmp = await Directory.systemTemp.createTemp('wraith_bench_');
  final a = await DeviceIdentity.loadOrCreate(Directory(p.join(tmp.path, 'a')));
  final b = await DeviceIdentity.loadOrCreate(Directory(p.join(tmp.path, 'b')));
  final inbox = await Directory(p.join(tmp.path, 'in')).create();
  final src = File(p.join(tmp.path, 'src.bin'));
  final rng = Random(1);
  final sink = src.openWrite();
  final block = Uint8List.fromList(List<int>.generate(1 << 20, (_) => rng.nextInt(256)));
  for (var i = 0; i < mib; i++) {
    sink.add(block);
  }
  await sink.close();
  final rx = TransferEngine(
    identity: b,
    trust: await TrustStore.load(Directory(p.join(tmp.path, 'b'))),
    saveDir: () async => inbox,
    onIncoming: (r) => r.respond(true),
    onJob: (_) {},
    basePort: 0,
  );
  await rx.start();
  final tx = TransferEngine(
    identity: a,
    trust: await TrustStore.load(Directory(p.join(tmp.path, 'a'))),
    saveDir: () async => tmp,
    onIncoming: (_) {},
    onJob: (_) {},
    basePort: 0,
  );
  late TransferJob job;
  final e2e = await _mbps(mib << 20, () async {
    job = await tx.send(
      Peer(id: b.fingerprint, name: 'b', platform: 'x', address: InternetAddress.loopbackIPv4, port: rx.port, lastSeen: DateTime.now()),
      [FileEntry(name: 'src.bin', size: mib << 20, path: src.path)],
    );
  });
  await rx.stop();
  await tmp.delete(recursive: true);
  pool.dispose();

  final cores = Platform.numberOfProcessors;
  final line = 'cores=$cores workers=${pool.workers} | AEAD inline ${inlineRate.toStringAsFixed(0)} MB/s · '
      'AEAD pool ${poolRate.toStringAsFixed(0)} MB/s · SHA-256 ${shaRate.toStringAsFixed(0)} MB/s · '
      'loopback transfer ${e2e.toStringAsFixed(0)} MB/s (${job.status.name}${job.error == null ? '' : ': ${job.error}'})';
  stdout.writeln('::notice title=Wraith benchmark ($arch)::$line');
  if (job.status != TransferStatus.done) exit(1);
  exit(0);
}
