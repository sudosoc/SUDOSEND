// SUDOSEND command-line client — same Wraith core as the app.
//
//   dart run bin/sudosend.dart --help
//   dart compile exe bin/sudosend.dart -o sudosend

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qr/qr.dart';
import 'package:wraith_core/discovery.dart';
import 'package:wraith_core/identity.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/pairing.dart';
import 'package:wraith_core/transfer.dart';
import 'package:wraith_core/util.dart';
import 'package:wraith_core/vault_windows.dart';
import 'package:wraith_core/wraith.dart';

const _version = '0.3.0';

const _usage = '''
SUDOSEND $_version — secure local file sharing (Wraith Protocol)

Usage:
  sudosend send <file|folder>... --to <device|ip[:port]>
  sudosend send --text "message" --to <device|ip[:port]>
  sudosend receive [--dir PATH] [--yes] [--trust] [--once] [--qr]
  sudosend devices [--wait SECONDS]
  sudosend id [--name NEW_NAME]

Targets:
  --to laptop        device name (case-insensitive prefix) or fingerprint prefix
  --to 192.168.1.20  IP address, optionally :port
  --to 'sudosend://pair?…'  pairing link (from a QR code) — no code to compare

Receive options:
  --dir PATH   where files are saved   (default: ~/Downloads/SUDOSEND)
  --yes        accept every request without asking (the code is still printed)
  --trust      remember accepted devices so they skip the code next time
  --once       exit after the first transfer
  --qr         print a pairing QR code: the device that scans it is trusted
               and accepted without a prompt (one use, valid 30 minutes)

Exit codes: 0 ok · 1 failed · 2 usage · 3 declined/not found · 130 interrupted
''';

class _Args {
  _Args(List<String> raw) {
    for (var i = 0; i < raw.length; i++) {
      final a = raw[i];
      if (a.startsWith('--')) {
        final eq = a.indexOf('=');
        if (eq > 0) {
          options[a.substring(2, eq)] = a.substring(eq + 1);
        } else if (_valued.contains(a.substring(2)) && i + 1 < raw.length) {
          options[a.substring(2)] = raw[++i];
        } else {
          flags.add(a.substring(2));
        }
      } else if (a == '-h') {
        flags.add('help');
      } else {
        positional.add(a);
      }
    }
  }

  static const _valued = {'to', 'dir', 'text', 'wait', 'name'};
  final List<String> positional = [];
  final Map<String, String> options = {};
  final Set<String> flags = {};
}

final bool _tty = stdout.hasTerminal;
String _c(String code, String s) => _tty ? '\x1B[${code}m$s\x1B[0m' : s;
String _cyan(String s) => _c('36', s);
String _green(String s) => _c('32', s);
String _red(String s) => _c('31', s);
String _yellow(String s) => _c('33;1', s);
String _dim(String s) => _c('2', s);

Directory _configDir() {
  final env = Platform.environment;
  if (Platform.isWindows) {
    return Directory(p.join(env['APPDATA'] ?? env['USERPROFILE'] ?? '.', 'sudosend'));
  }
  final base = env['XDG_CONFIG_HOME'] ?? p.join(env['HOME'] ?? '.', '.config');
  return Directory(p.join(base, 'sudosend'));
}

Directory _defaultInbox() {
  final env = Platform.environment;
  final home = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
  return Directory(p.join(home ?? '.', 'Downloads', 'SUDOSEND'));
}

Future<void> main(List<String> raw) async {
  final args = _Args(raw);
  int code;
  try {
    code = await _run(args);
  } on WraithException catch (e) {
    stderr.writeln(_red('error: ${e.message}'));
    code = 1;
  } catch (e) {
    stderr.writeln(_red('error: ${describeError(e)}'));
    code = 1;
  }
  await stdout.flush();
  exit(code);
}

Future<int> _run(_Args args) async {
  if (args.flags.contains('version')) {
    stdout.writeln('sudosend $_version');
    return 0;
  }
  if (args.positional.isEmpty && args.flags.isEmpty && args.options.isEmpty && await _launchApp()) {
    return 0;
  }
  if (args.positional.isEmpty || args.flags.contains('help')) {
    stdout.write(_usage);
    return args.positional.isEmpty && !args.flags.contains('help') ? 2 : 0;
  }
  final config = _configDir();
  final identity = await DeviceIdentity.loadOrCreate(config, vault: DpapiVault.supported ? DpapiVault() : null);
  final trust = await TrustStore.load(config);
  final command = args.positional.first;
  final rest = args.positional.sublist(1);

  switch (command) {
    case 'id':
      final newName = args.options['name'];
      if (newName != null) await identity.rename(newName);
      stdout.writeln('${_cyan(identity.name)}  ${platformName()}');
      stdout.writeln('fingerprint  ${groupFingerprint(identity.fingerprint)}');
      stdout.writeln(_dim('key storage  ${identity.protection}'));
      stdout.writeln(_dim('identity     ${config.path}'));
      return 0;
    case 'devices':
      return _devices(identity, int.tryParse(args.options['wait'] ?? '') ?? 4);
    case 'send':
      return _send(identity, trust, rest, args);
    case 'receive':
      return _receive(identity, trust, args);
    default:
      stderr.writeln(_red('unknown command "$command"\n'));
      stdout.write(_usage);
      return 2;
  }
}

/// `sudosend` with no arguments opens the desktop app when it is installed
/// next to the CLI (Windows installer puts the CLI in <app>\\cli\\).
Future<bool> _launchApp() async {
  final here = p.dirname(Platform.resolvedExecutable);
  final candidates = Platform.isWindows
      ? [p.join(here, '..', 'sudosend.exe')]
      : [p.join(here, 'sudosend'), '/opt/sudosend/sudosend'];
  for (final c in candidates) {
    final f = File(p.normalize(c));
    if (f.path == Platform.resolvedExecutable) continue;
    if (await f.exists()) {
      await Process.start(f.path, const [], mode: ProcessStartMode.detached);
      return true;
    }
  }
  return false;
}

// ─────────────────────────── devices ───────────────────────────

Future<List<Peer>> _discover(DeviceIdentity identity, Duration wait, {bool Function(List<Peer>)? until}) async {
  final discovery = Discovery(identity: identity, transferPort: kTransferPort, onChanged: () {}, passive: true);
  await discovery.start();
  final deadline = DateTime.now().add(wait);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (until != null && until(discovery.peers)) break;
  }
  final peers = discovery.peers;
  await discovery.stop();
  return peers;
}

Future<int> _devices(DeviceIdentity identity, int seconds) async {
  stdout.writeln(_dim('scanning for ${seconds}s…'));
  final peers = await _discover(identity, Duration(seconds: seconds));
  if (peers.isEmpty) {
    stdout.writeln('no devices found — is SUDOSEND open on the same network?');
    return 3;
  }
  for (final peer in peers) {
    stdout.writeln('${_cyan(peer.name.padRight(24))} ${peer.platform.padRight(8)} '
        '${peer.address.address}:${peer.port}  ${_dim(groupFingerprint(peer.id, groups: 2))}');
  }
  return 0;
}

// ─────────────────────────── send ───────────────────────────

Future<List<FileEntry>> _collect(List<String> paths) async {
  final files = <FileEntry>[];
  for (final raw in paths) {
    final type = await FileSystemEntity.type(raw);
    if (type == FileSystemEntityType.file) {
      final f = File(raw);
      files.add(FileEntry(name: p.basename(f.path), size: await f.length(), path: f.absolute.path));
    } else if (type == FileSystemEntityType.directory) {
      final root = Directory(raw).absolute;
      final rootName = p.basename(p.normalize(root.path));
      await for (final e in root.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final rel = p.relative(e.path, from: root.path).split(p.separator).join('/');
        files.add(FileEntry(name: '$rootName/$rel', size: await e.length(), path: e.path));
      }
    } else {
      throw WraithException('not found: $raw');
    }
  }
  return files;
}

Future<Peer?> _resolve(DeviceIdentity identity, String target) async {
  final pairing = PairingInfo.tryParse(target);
  if (pairing != null) return pairing.toPeer();
  final hostPort = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$').firstMatch(target);
  if (hostPort != null) {
    final address = InternetAddress.tryParse(hostPort.group(1)!);
    final port = int.tryParse(hostPort.group(2) ?? '') ?? kTransferPort;
    if (address == null || port < 1 || port > 65535) return null;
    return Peer.manual(address, port);
  }
  final needle = target.toLowerCase();
  bool matches(Peer peer) =>
      peer.name.toLowerCase().startsWith(needle) || peer.id.toLowerCase().startsWith(needle.replaceAll(' ', ''));
  stdout.writeln(_dim('looking for "$target"…'));
  final peers = await _discover(identity, const Duration(seconds: 6), until: (ps) => ps.any(matches));
  final hits = peers.where(matches).toList();
  if (hits.length > 1) {
    stderr.writeln(_yellow('"$target" matches several devices: ${hits.map((h) => h.name).join(', ')}'));
    return null;
  }
  return hits.isEmpty ? null : hits.first;
}

Future<int> _send(DeviceIdentity identity, TrustStore trust, List<String> paths, _Args args) async {
  final target = args.options['to'];
  final text = args.options['text'];
  if (target == null || (paths.isEmpty && text == null)) {
    stderr.writeln(_red('send needs files (or --text) and --to\n'));
    stdout.write(_usage);
    return 2;
  }
  final files = text == null ? await _collect(paths) : <FileEntry>[];
  if (text == null && files.isEmpty) throw const WraithException('nothing to send (empty folder?)');

  final peer = await _resolve(identity, target);
  if (peer == null) {
    stderr.writeln(_red('device "$target" not found'));
    return 3;
  }

  TransferJob? current;
  final engine = TransferEngine(
    identity: identity,
    trust: trust,
    saveDir: () async => _defaultInbox(),
    onIncoming: (r) => r.respond(false),
    onJob: (job) {
      current = job;
      final progress = _ProgressPrinter(job);
      var shownCode = false;
      job.changes.listen((_) {
        if (!shownCode && job.status == TransferStatus.awaitingApproval) {
          shownCode = true;
          if (job.peerTrusted) {
            stdout.writeln(_green('  trusted device') + _dim(' · waiting for ${job.peerName} to accept…'));
          } else {
            stdout.writeln('  verification code: ${_yellow(formatSas(job.sas ?? ''))}  '
                '${_dim('(must match ${job.peerName}\'s screen)')}');
            stdout.writeln(_dim('  waiting for ${job.peerName} to accept…'));
          }
        }
        progress.render();
        if (!job.isActive) progress.finish();
      });
    },
  );

  final total = files.fold<int>(0, (a, f) => a + f.size);
  stdout.writeln('→ ${_cyan(peer.name)}  '
      '${text != null ? 'text (${text.length} chars)' : '${files.length} file(s), ${formatBytes(total)}'}');

  final sigint = ProcessSignal.sigint.watch().listen((_) {
    current?.cancel();
    stderr.writeln(_yellow('\ncancelling…'));
  });
  final job = await engine.send(peer, files, text: text, pairToken: PairingInfo.tryParse(target)?.token);
  await sigint.cancel();
  return _reportSend(job);
}

int _reportSend(TransferJob job) {
  switch (job.status) {
    case TransferStatus.done:
      stdout.writeln(_green('✔ delivered and SHA-256 verified by ${job.peerName}'));
      return 0;
    case TransferStatus.declined:
      stdout.writeln(_yellow('✖ ${job.peerName} declined'));
      return 3;
    case TransferStatus.cancelled:
      stdout.writeln(_yellow('✖ cancelled'));
      return 130;
    default:
      stderr.writeln(_red('✖ ${job.error ?? 'failed'}'));
      return 1;
  }
}

// ─────────────────────────── receive ───────────────────────────

Future<int> _receive(DeviceIdentity identity, TrustStore trust, _Args args) async {
  final dir = Directory(args.options['dir'] ?? _defaultInbox().path).absolute;
  await dir.create(recursive: true);
  final autoAccept = args.flags.contains('yes');
  final autoTrust = args.flags.contains('trust');
  final once = args.flags.contains('once');
  final finished = Completer<int>();

  late final TransferEngine engine;
  engine = TransferEngine(
    identity: identity,
    trust: trust,
    saveDir: () async => dir,
    onIncoming: (request) {
      stdout.writeln();
      stdout.writeln('${_cyan('⇣ ${request.peerName}')} (${request.peerPlatform})  '
          '${_dim(groupFingerprint(request.fingerprint, groups: 4))}');
      if (request.text != null) {
        stdout.writeln('  text, ${request.text!.length} chars');
      } else {
        for (final f in request.files.take(8)) {
          stdout.writeln('  ${f.name}  ${_dim(formatBytes(f.size))}');
        }
        if (request.files.length > 8) stdout.writeln('  + ${request.files.length - 8} more');
        stdout.writeln('  total ${formatBytes(request.totalBytes)}');
      }
      if (request.trusted) {
        stdout.writeln(_green('  trusted device'));
      } else {
        stdout.writeln('  verification code: ${_yellow(formatSas(request.sas))}  '
            '${_dim('(must match the sender)')}');
      }
      if (autoAccept) {
        request.respond(true, trust: autoTrust);
        return;
      }
      stdout.write('  accept? [y/N/t=trust/b=block] ');
      unawaited(_nextLine().then((line) {
        final answer = line.trim().toLowerCase();
        final yes = answer == 'y' || answer == 'yes' || answer == 't';
        request.respond(yes, trust: answer == 't' || autoTrust, block: answer == 'b');
        if (!yes) {
          stdout.writeln(_dim(answer == 'b' ? '  blocked' : '  declined'));
          if (once && !finished.isCompleted) finished.complete(3);
        }
      }));
    },
    onRejected: (address, reason) => stderr.writeln(_dim('  refused $address ($reason)')),
    autoAccept: (request) => request.trusted,
    onJob: (job) {
      final progress = _ProgressPrinter(job);
      if (job.direction == TransferDirection.incoming) {
        stdout.writeln('${_cyan('⇣ receiving from ${job.peerName}')}'
            '${job.peerTrusted ? _green(' (trusted)') : ''}');
      }
      job.changes.listen((_) {
        progress.render();
        if (job.isActive) return;
        progress.finish();
        if (job.status == TransferStatus.done) {
          if (job.text != null) {
            stdout.writeln(_green('✔ text received:'));
            stdout.writeln(job.text);
          } else {
            stdout.writeln(_green('✔ ${job.verifiedFiles} file(s) verified → ${dir.path}'));
          }
        } else {
          stdout.writeln(_red('✖ ${job.error ?? job.status.name}'));
        }
        if (once && !finished.isCompleted) finished.complete(job.status == TransferStatus.done ? 0 : 1);
      });
    },
  );
  await engine.start();
  final discovery = Discovery(identity: identity, transferPort: engine.port, onChanged: () {});
  await discovery.start();

  stdout.writeln('${_cyan(identity.name)} is visible on port ${engine.port}');
  stdout.writeln('fingerprint ${groupFingerprint(identity.fingerprint)}');
  stdout.writeln(_dim('saving to ${dir.path} · Ctrl+C to stop'));
  if (args.flags.contains('qr')) {
    final addresses = await _localAddresses();
    if (addresses.isEmpty) {
      stderr.writeln(_yellow('no network address found — cannot build a pairing QR'));
    } else {
      final link = PairingInfo(
        name: identity.name,
        fingerprint: identity.fingerprint,
        addresses: addresses,
        port: engine.port,
        token: engine.createPairingToken(ttl: const Duration(minutes: 30)),
      ).toUri();
      stdout.writeln();
      stdout.write(renderQr(link));
      stdout.writeln(_dim('scan with SUDOSEND, or: sudosend send <file> --to \'$link\''));
    }
  }

  final sub = ProcessSignal.sigint.watch().listen((_) {
    if (!finished.isCompleted) finished.complete(130);
  });
  final code = await finished.future;
  await sub.cancel();
  await discovery.stop();
  await engine.stop();
  return code;
}

final Stream<String> _stdinLines = stdin.transform(utf8.decoder).transform(const LineSplitter()).asBroadcastStream();

Future<String> _nextLine() => _stdinLines.first.catchError((Object _) => '');

Future<List<InternetAddress>> _localAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a,
    ];
  } catch (_) {
    return const [];
  }
}

/// Renders [data] as a terminal QR code (black on white, two rows per line).
String renderQr(String data) {
  final image = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.L));
  final n = image.moduleCount;
  const quiet = 2;
  bool dark(int row, int col) =>
      row >= 0 && col >= 0 && row < n && col < n && image.isDark(row, col);
  final out = StringBuffer();
  for (var row = -quiet; row < n + quiet; row += 2) {
    out.write('\x1B[30;47m');
    for (var col = -quiet; col < n + quiet; col++) {
      final top = dark(row, col);
      final bottom = dark(row + 1, col);
      out.write(top && bottom ? '█' : top ? '▀' : bottom ? '▄' : ' ');
    }
    out.write('\x1B[0m\n');
  }
  return out.toString();
}

class _ProgressPrinter {
  _ProgressPrinter(this.job);
  final TransferJob job;
  bool _drew = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void render() {
    if (job.isText || job.status != TransferStatus.transferring) return;
    final now = DateTime.now();
    if (!_tty && now.difference(_last) < const Duration(seconds: 2)) return;
    _last = now;
    const width = 28;
    final filled = (job.progress * width).round();
    final bar = '${'█' * filled}${'░' * (width - filled)}';
    final line = '  $bar ${(job.progress * 100).toStringAsFixed(0).padLeft(3)}%  '
        '${formatBytes(job.doneBytes)}/${formatBytes(job.totalBytes)}  ${formatSpeed(job.speed)}';
    if (_tty) {
      stdout.write('\r$line   ');
    } else {
      stdout.writeln(line);
    }
    _drew = true;
  }

  void finish() {
    if (_drew && _tty) stdout.writeln();
  }
}
