import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'identity.dart';
import 'models.dart';
import 'pairing.dart';
import 'util.dart';
import 'wraith.dart';

const int kMaxTextLength = 64 * 1024;

class IncomingDecision {
  const IncomingDecision(this.accept, {this.trust = false, this.block = false});
  final bool accept;
  final bool trust;

  /// Decline and block this device's fingerprint from now on.
  final bool block;
}

/// A pending "X wants to send you N files / a text" request shown to the user.
class IncomingRequest {
  IncomingRequest({
    required this.peerName,
    required this.peerPlatform,
    required this.peerAddress,
    required this.fingerprint,
    required this.sas,
    required this.trusted,
    required this.files,
    this.text,
    this.paired = false,
  })  : id = '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
        totalBytes = files.fold<int>(0, (a, f) => a + f.size);

  static int _seq = 0;

  final String id;
  final String peerName;
  final String peerPlatform;
  final String peerAddress;
  final String fingerprint;
  final String sas;
  final bool trusted;
  final List<FileEntry> files;
  final String? text;
  final int totalBytes;

  /// The sender presented a valid one-time QR pairing token.
  final bool paired;

  final Completer<IncomingDecision> _completer = Completer<IncomingDecision>();
  Future<IncomingDecision> get decision => _completer.future;
  bool get isPending => !_completer.isCompleted;

  void respond(bool accept, {bool trust = false, bool block = false}) {
    if (!_completer.isCompleted) {
      _completer.complete(IncomingDecision(accept && !block, trust: trust, block: block));
    }
  }
}

/// Limits that keep a hostile device on the LAN from flooding us with
/// connections or prompts.
class ConnectionLimits {
  const ConnectionLimits({
    this.maxActive = 8,
    this.maxActivePerIp = 3,
    this.maxPerMinutePerIp = 20,
    this.maxPendingPrompts = 3,
  });

  final int maxActive;
  final int maxActivePerIp;
  final int maxPerMinutePerIp;
  final int maxPendingPrompts;
}

class _Target {
  _Target(this.dir, this.baseName, this.part, this.offset);
  final Directory dir;
  final String baseName;
  final File part;
  final int offset;
}

class TransferEngine {
  TransferEngine({
    required this.identity,
    required this.trust,
    required this.saveDir,
    required this.onIncoming,
    required this.onJob,
    this.autoAccept,
    this.onRejected,
    this.limits = const ConnectionLimits(),
    this.basePort = kTransferPort,
  });

  final DeviceIdentity identity;
  final TrustStore trust;
  final Future<Directory> Function() saveDir;
  final void Function(IncomingRequest request) onIncoming;
  final void Function(TransferJob job) onJob;

  /// Return true to accept a request without asking (e.g. trusted devices).
  final bool Function(IncomingRequest request)? autoAccept;

  /// Called when a connection or request is refused by the flood limits or
  /// the block list. [reason] is a short machine-readable tag.
  final void Function(String address, String reason)? onRejected;

  final ConnectionLimits limits;

  /// First port to try; 0 means "any free port" (used by tests).
  final int basePort;

  ServerSocket? _server;
  int port = kTransferPort;

  int rejectedConnections = 0;
  int _active = 0;
  final Map<String, int> _activeByIp = {};
  final Map<String, List<int>> _hitsByIp = {};
  final Set<String> _promptingIps = {};
  int _pendingPrompts = 0;
  final Map<String, DateTime> _pairTokens = {};

  static const Duration _approvalTimeout = Duration(minutes: 2);
  static const Duration _idleTimeout = Duration(seconds: 30);

  Future<void> start() async {
    final attempts = basePort == 0 ? 1 : 10;
    for (var i = 0; i < attempts; i++) {
      try {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, basePort == 0 ? 0 : basePort + i);
        break;
      } on SocketException {
        continue;
      }
    }
    final server = _server;
    if (server == null) {
      throw const WraithException('Could not open a listening port (47824–47833 busy)');
    }
    port = server.port;
    server.listen(_onConnection);
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  // ─────────────────────────── Pairing tokens ───────────────────────────

  /// Creates a one-time token for a QR code / pairing link.
  String createPairingToken({Duration ttl = const Duration(minutes: 10)}) {
    _prunePairTokens();
    final token = newPairingToken();
    _pairTokens[token] = DateTime.now().add(ttl);
    return token;
  }

  void revokePairingToken(String token) => _pairTokens.remove(token);

  void _prunePairTokens() {
    final now = DateTime.now();
    _pairTokens.removeWhere((_, expiry) => expiry.isBefore(now));
  }

  bool _consumePairingToken(String? token) {
    if (token == null) return false;
    _prunePairTokens();
    String? match;
    for (final candidate in _pairTokens.keys) {
      if (constantTimeEquals(utf8.encode(candidate), utf8.encode(token))) match = candidate;
    }
    if (match == null) return false;
    _pairTokens.remove(match);
    return true;
  }

  // ─────────────────────────── Flood control ───────────────────────────

  void _onConnection(Socket socket) {
    final ip = socket.remoteAddress.address;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hits = _hitsByIp.putIfAbsent(ip, () => <int>[])
      ..removeWhere((t) => now - t > 60000)
      ..add(now);
    if (_hitsByIp.length > 4096) {
      _hitsByIp.removeWhere((_, v) => v.isEmpty || now - v.last > 60000);
    }
    String? reason;
    if (_active >= limits.maxActive) {
      reason = 'busy';
    } else if ((_activeByIp[ip] ?? 0) >= limits.maxActivePerIp) {
      reason = 'too-many-connections';
    } else if (hits.length > limits.maxPerMinutePerIp) {
      reason = 'rate-limit';
    }
    if (reason != null) {
      rejectedConnections++;
      socket.destroy();
      onRejected?.call(ip, reason);
      return;
    }
    _active++;
    _activeByIp[ip] = (_activeByIp[ip] ?? 0) + 1;
    unawaited(_handleIncoming(socket, ip).whenComplete(() {
      _active--;
      final left = (_activeByIp[ip] ?? 1) - 1;
      if (left <= 0) {
        _activeByIp.remove(ip);
      } else {
        _activeByIp[ip] = left;
      }
    }));
  }

  // ─────────────────────────── Sending ───────────────────────────

  Future<Socket> _connect(Peer peer) async {
    final addresses = [peer.address, ...peer.alternates];
    Object? lastError;
    for (final address in addresses) {
      try {
        return await Socket.connect(address, peer.port,
            timeout: addresses.length == 1 ? const Duration(seconds: 8) : const Duration(seconds: 4));
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const WraithException('No address to connect to');
  }

  /// Sends [files] (or a [text] message when [files] is empty) to [peer].
  /// [pairToken] comes from a scanned QR code / pairing link.
  /// Completes when the transfer has finished, successfully or not.
  Future<TransferJob> send(Peer peer, List<FileEntry> files, {String? text, String? pairToken}) async {
    if (text != null && text.length > kMaxTextLength) {
      throw const WraithException('Text is too long (64 KB max)');
    }
    final job = TransferJob(
      direction: TransferDirection.outgoing,
      peerName: peer.name,
      peerPlatform: peer.platform,
      files: files,
      text: text,
      status: TransferStatus.connecting,
    );
    onJob(job);

    Socket? socket;
    SecureChannel? channel;
    RandomAccessFile? raf;
    try {
      socket = await _connect(peer);
      socket.setOption(SocketOption.tcpNoDelay, true);
      final reader = FrameReader(socket);
      final hs = await wraithHandshake(socket: socket, reader: reader, me: identity, initiator: true);
      channel = hs.channel;

      if (!peer.manual && hs.peerFingerprint != peer.id) {
        throw const WraithException(
            'Fingerprint mismatch — the device that answered is not the one advertised. Possible spoofing.');
      }
      if (trust.isBlocked(hs.peerFingerprint)) {
        throw const WraithException('This device is on your block list');
      }
      // A scanned QR code proves the receiver's key out of band.
      if (pairToken != null && !peer.manual && !trust.isTrusted(hs.peerFingerprint)) {
        await trust.add(hs.peerFingerprint, hs.peerName);
      }
      final trusted = trust.isTrusted(hs.peerFingerprint);
      job.update(() {
        job.peerName = hs.peerName;
        job.peerPlatform = hs.peerPlatform;
        job.peerFingerprint = hs.peerFingerprint;
        job.peerTrusted = trusted;
        job.sas = hs.sas;
        job.status = TransferStatus.awaitingApproval;
      });

      await channel.sendJson(Frame.offer, {
        'files': [for (final f in files) {'name': f.name, 'size': f.size}],
        if (text != null) 'text': text,
        if (pairToken != null) 'pair': pairToken,
      });

      final reply = await channel.receive(timeout: _approvalTimeout + const Duration(seconds: 10));
      if (reply.type == Frame.decline) {
        job.finish(TransferStatus.declined);
        return job;
      }
      if (reply.type != Frame.accept) {
        throw const WraithException('Protocol violation (expected accept/decline)');
      }
      final acceptBody = reply.body.isEmpty ? const <String, dynamic>{} : reply.json();
      final resume = acceptBody['resume'];

      job.update(() => job.status = TransferStatus.transferring);
      final clock = Stopwatch()..start();

      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        var offset = 0;
        if (resume is Map) {
          final o = resume['$i'];
          if (o is int && o > 0 && o <= f.size) offset = o;
        }

        final hasher = Sha256Stream();
        raf = await File(f.path!).open();

        // Resume: the receiver already holds [offset] bytes. Hash them locally
        // so the final SHA-256 still covers the whole file, but don't send them.
        var skipped = 0;
        while (skipped < offset) {
          final chunk = await raf.read(min(kChunkSize, offset - skipped));
          if (chunk.isEmpty) throw WraithException('"${f.name}" changed while sending');
          hasher.add(chunk);
          skipped += chunk.length;
        }
        if (offset > 0) {
          job.resumedBytes += offset;
          job.addProgress(offset, clock);
        }

        await channel.sendJson(Frame.fileStart, {'i': i, 'name': f.name, 'size': f.size, 'offset': offset});
        var remaining = f.size - offset;
        while (remaining > 0) {
          if (job.cancelRequested) {
            await channel.send(Frame.cancel);
            throw const WraithException('Cancelled');
          }
          final chunk = await raf.read(min(kChunkSize, remaining));
          if (chunk.isEmpty) throw WraithException('"${f.name}" changed while sending');
          hasher.add(chunk);
          await channel.send(Frame.data, chunk, false);
          remaining -= chunk.length;
          job.addProgress(chunk.length, clock);
        }
        await raf.close();
        raf = null;
        await channel.sendJson(Frame.fileEnd, {'i': i, 'sha256': base64Encode(hasher.close())});
      }

      await channel.send(Frame.done);
      job.update(() => job.status = TransferStatus.verifying);
      final result = (await channel.expect(Frame.result, timeout: _idleTimeout)).json();
      if (result['ok'] != true) throw const WraithException('Receiver could not verify the files');
      job.update(() => job.verifiedFiles = files.length);
      job.finish(TransferStatus.done);
    } catch (e) {
      job.fail(e);
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
      if (channel != null) {
        await channel.close();
      } else {
        socket?.destroy();
      }
    }
    return job;
  }

  // ─────────────────────────── Receiving ───────────────────────────

  Future<void> _handleIncoming(Socket socket, String ip) async {
    SecureChannel? channel;
    TransferJob? job;
    RandomAccessFile? raf;
    File? partFile;
    var keepPartial = false;
    var prompting = false;
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      final reader = FrameReader(socket);
      final hs = await wraithHandshake(socket: socket, reader: reader, me: identity, initiator: false);
      channel = hs.channel;

      final offer = (await channel.expect(Frame.offer, timeout: _idleTimeout)).json();
      final rawFiles = offer['files'];
      final rawText = offer['text'];
      final rawPair = offer['pair'];
      if (rawFiles is! List || rawFiles.length > 100000) throw const WraithException('Invalid offer');
      if (rawText != null && (rawText is! String || rawText.length > kMaxTextLength)) {
        throw const WraithException('Invalid text offer');
      }
      final text = rawText as String?;
      if (rawFiles.isEmpty && text == null) throw const WraithException('Empty offer');

      final files = <FileEntry>[];
      final segments = <List<String>>[];
      for (final f in rawFiles) {
        if (f is! Map) throw const WraithException('Invalid offer');
        final name = f['name'];
        final size = f['size'];
        if (name is! String || size is! int || size < 0) throw const WraithException('Invalid offer');
        final segs = sanitizeRelativePath(name);
        segments.add(segs);
        files.add(FileEntry(name: segs.join('/'), size: size));
      }

      // Read the offer before declining a blocked device, so the reply is not
      // lost to a TCP reset caused by unread data.
      if (trust.isBlocked(hs.peerFingerprint)) {
        onRejected?.call(ip, 'blocked');
        await channel.send(Frame.decline);
        return;
      }

      final paired = _consumePairingToken(rawPair is String ? rawPair : null);
      if (paired && !trust.isTrusted(hs.peerFingerprint)) {
        await trust.add(hs.peerFingerprint, hs.peerName);
      }
      final trusted = trust.isTrusted(hs.peerFingerprint);
      final request = IncomingRequest(
        peerName: hs.peerName,
        peerPlatform: hs.peerPlatform,
        peerAddress: ip,
        fingerprint: hs.peerFingerprint,
        sas: hs.sas,
        trusted: trusted,
        files: files,
        text: text,
        paired: paired,
      );

      if (paired || (autoAccept?.call(request) ?? false)) {
        request.respond(true);
      } else {
        // One open prompt per address and a small global cap, so nobody can
        // bury the user under dialogs.
        if (_promptingIps.contains(ip) || _pendingPrompts >= limits.maxPendingPrompts) {
          onRejected?.call(ip, 'prompt-flood');
          await channel.send(Frame.decline);
          return;
        }
        _promptingIps.add(ip);
        _pendingPrompts++;
        prompting = true;
        onIncoming(request);
      }
      final decision = await request.decision.timeout(
        _approvalTimeout,
        onTimeout: () {
          request.respond(false);
          return const IncomingDecision(false);
        },
      );
      if (prompting) {
        prompting = false;
        _promptingIps.remove(ip);
        _pendingPrompts--;
      }
      if (decision.block) {
        await trust.block(hs.peerFingerprint, hs.peerName);
      }
      if (!decision.accept) {
        await channel.send(Frame.decline);
        return;
      }
      if (decision.trust && !trusted) await trust.add(hs.peerFingerprint, hs.peerName);

      // Work out where every file goes and whether a partial copy from an
      // earlier, interrupted attempt by the same device can be resumed.
      final root = await saveDir();
      await root.create(recursive: true);
      final targets = <_Target>[];
      final resume = <String, int>{};
      for (var i = 0; i < files.length; i++) {
        final segs = segments[i];
        final dir = Directory(p.joinAll([root.path, ...segs.sublist(0, segs.length - 1)]));
        final base = segs.last;
        final part = File(p.join(dir.path, '.$base.${hs.peerFingerprint.substring(0, 8)}-${files[i].size}.sudosend-part'));
        if (!p.isWithin(root.path, part.path)) throw const WraithException('Unsafe path rejected');
        var offset = 0;
        if (await part.exists()) {
          final len = await part.length();
          if (len > 0 && len <= files[i].size) {
            offset = len;
          } else {
            await part.delete();
          }
        }
        if (offset > 0) resume['$i'] = offset;
        targets.add(_Target(dir, base, part, offset));
      }

      final activeJob = TransferJob(
        direction: TransferDirection.incoming,
        peerName: hs.peerName,
        peerPlatform: hs.peerPlatform,
        files: files,
        text: text,
        status: TransferStatus.transferring,
      )
        ..peerFingerprint = hs.peerFingerprint
        ..peerTrusted = trusted || decision.trust || paired
        ..sas = hs.sas;
      job = activeJob;
      onJob(activeJob);
      await channel.sendJson(Frame.accept, {'resume': resume});

      final clock = Stopwatch()..start();
      var index = -1;
      var written = 0;
      Sha256Stream? hasher;

      while (true) {
        final msg = await channel.receive(timeout: _idleTimeout);
        if (activeJob.cancelRequested) {
          await channel.send(Frame.cancel);
          throw const WraithException('Cancelled');
        }

        if (msg.type == Frame.fileStart) {
          final m = msg.json();
          final i = m['i'];
          if (i is! int || i != index + 1 || i >= files.length || raf != null) {
            throw const WraithException('Protocol violation (file order)');
          }
          final target = targets[i];
          if (m['offset'] != target.offset) throw const WraithException('Protocol violation (resume offset)');
          index = i;
          written = target.offset;
          final h = Sha256Stream();
          hasher = h;
          await target.dir.create(recursive: true);
          partFile = target.part;
          if (target.offset > 0) {
            await for (final chunk in target.part.openRead(0, target.offset)) {
              h.add(chunk);
            }
            raf = await target.part.open(mode: FileMode.append);
            activeJob.resumedBytes += target.offset;
            activeJob.addProgress(target.offset, clock);
          } else {
            raf = await target.part.open(mode: FileMode.write);
          }
        } else if (msg.type == Frame.data) {
          final out = raf;
          final h = hasher;
          if (out == null || h == null) throw const WraithException('Protocol violation (data outside file)');
          written += msg.body.length;
          if (written > files[index].size) {
            throw const WraithException('Sender exceeded the announced file size');
          }
          await out.writeFrom(msg.body);
          h.add(msg.body);
          activeJob.addProgress(msg.body.length, clock);
        } else if (msg.type == Frame.fileEnd) {
          final out = raf;
          final h = hasher;
          final part = partFile;
          if (out == null || h == null || part == null) {
            throw const WraithException('Protocol violation (unexpected end of file)');
          }
          if (written != files[index].size) throw const WraithException('File truncated');
          final m = msg.json();
          final expected = base64Decode(m['sha256'] as String);
          await out.close();
          raf = null;
          if (!constantTimeEquals(h.close(), expected)) {
            throw WraithException('SHA-256 mismatch on "${files[index].name}" — file discarded');
          }
          final dest = await uniqueFile(targets[index].dir, targets[index].baseName);
          await part.rename(dest.path);
          partFile = null;
          hasher = null;
          activeJob.update(() {
            activeJob.savedPaths.add(dest.path);
            activeJob.verifiedFiles++;
          });
        } else if (msg.type == Frame.done) {
          if (index != files.length - 1 || raf != null) {
            throw const WraithException('Transfer ended early');
          }
          await channel.sendJson(Frame.result, {'ok': true, 'verified': files.length});
          activeJob.finish(TransferStatus.done);
          return;
        } else if (msg.type == Frame.cancel) {
          throw const WraithException('Cancelled by the sender');
        } else if (msg.type == Frame.error) {
          throw WraithException('Sender reported: ${utf8.decode(msg.body, allowMalformed: true)}');
        } else {
          throw WraithException('Protocol violation (unexpected frame ${msg.type})');
        }
      }
    } catch (e) {
      // Keep partial data after a dropped connection so the next attempt can
      // resume; discard it after cancels, integrity or protocol failures.
      keepPartial = e is SocketException ||
          e is TimeoutException ||
          (e is WraithException && e.message.startsWith('Connection closed'));
      job?.fail(e);
    } finally {
      if (prompting) {
        _promptingIps.remove(ip);
        _pendingPrompts--;
      }
      try {
        await raf?.close();
      } catch (_) {}
      final leftover = partFile;
      if (leftover != null && !keepPartial) {
        try {
          if (await leftover.exists()) await leftover.delete();
        } catch (_) {}
      }
      if (channel != null) {
        await channel.close();
      } else {
        socket.destroy();
      }
    }
  }
}
