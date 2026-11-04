import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'hashing.dart';
import 'identity.dart';
import 'journal.dart';
import 'models.dart';
import 'pairing.dart';
import 'receipt.dart';
import 'sync.dart';
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
    this.clipboard = false,
    this.ring = false,
    this.chat = false,
    this.speedTest = false,
    this.syncInvite,
    this.syncId,
    this.previews = const {},
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

  /// A universal-clipboard push (text only).
  final bool clipboard;

  /// "Find my device": make this device ring (no files, trusted senders only).
  final bool ring;

  /// A chat message.
  final bool chat;

  /// A speed test (random data, discarded).
  final bool speedTest;

  /// Invitation to sync a folder: (id, folder name).
  final ({String id, String name})? syncInvite;

  /// Files for an existing sync pair.
  final String? syncId;

  /// Image previews by file index (PNG/JPEG bytes, already size-checked).
  final Map<int, Uint8List> previews;

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
    this.saveDirFor,
    this.limits = const ConnectionLimits(),
    this.basePort = kTransferPort,
  });

  final DeviceIdentity identity;
  final TrustStore trust;
  final Future<Directory> Function() saveDir;

  /// Optional per-sender destination (e.g. a subfolder named after the device).
  final Future<Directory> Function(String peerName, String fingerprint)? saveDirFor;

  /// Optional smart placement: maps a received file's relative path to its
  /// path under the inbox (e.g. device/category/date/name). Not used for
  /// folder sync. Every returned segment is re-sanitized here.
  List<String> Function(String peerName, String fingerprint, List<String> segments)? placeFile;

  /// Write-ahead journal for multi-step file operations (Smart Recovery).
  Journal? journal;

  /// Search from another device: return result maps (or null to refuse).
  /// Only ever called for trusted devices.
  List<Map<String, Object?>>? Function(String fingerprint, Map<String, dynamic> query)? onSearch;

  /// Another device asks this one to send it a file by SHA-256 (hex).
  /// Return true if the file will be sent. Only called for trusted devices.
  bool Function(String fingerprint, String sha256)? onFetch;
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

  /// Upload speed cap in bytes per second for outgoing files (0 = unlimited).
  static int maxBytesPerSecond = 0;

  /// Smart compression of compressible files (needs receiver support).
  static bool compression = true;

  /// Resolves a folder-sync pair to its local folder, or null if this device
  /// has no such pair with that fingerprint.
  Directory? Function(String syncId, String fingerprint)? syncFolder;

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

  /// True while [token] is unused and unexpired.
  bool isPairingTokenValid(String token) {
    _prunePairTokens();
    return _pairTokens.containsKey(token);
  }

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
  Future<TransferJob> send(Peer peer, List<FileEntry> files,
      {String? text,
      String? pairToken,
      bool clipboard = false,
      bool ring = false,
      bool chat = false,
      Map<int, Uint8List>? previews,
      String? syncId}) async {
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
    )
      ..clipboard = clipboard && text != null
      ..ring = ring && files.isEmpty && text == null
      ..chat = chat && text != null
      ..syncId = syncId
      ..peerAddress = peer.address.address
      ..peerPort = peer.port;
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
        'files': [
          for (final f in files) {'name': f.name, 'size': f.size, if (f.mtime != null) 'mtime': f.mtime},
        ],
        if (job.chat) 'chat': true,
        if (syncId != null) 'sync': syncId,
        if (previews != null && previews.isNotEmpty)
          'previews': {for (final e in previews.entries.take(8)) '${e.key}': base64Encode(e.value)},
        if (text != null) 'text': text,
        if (pairToken != null) 'pair': pairToken,
        if (clipboard && text != null) 'clip': true,
        if (job.ring) 'ring': true,
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
      final caps = acceptBody['caps'];
      final canCompress = compression && caps is List && caps.contains('z');

      job.update(() => job.status = TransferStatus.transferring);
      final clock = Stopwatch()..start();
      final sent = <ReceiptFile>[];
      var paced = 0;

      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        var offset = 0;
        if (resume is Map) {
          final o = resume['$i'];
          if (o is int && o > 0 && o <= f.size) offset = o;
        }

        final hasher = ChunkHasher.create(f.size);
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
        var tryCompress = canCompress && worthCompressing(f.name);
        var misses = 0;
        while (remaining > 0) {
          if (job.cancelRequested) {
            await channel.send(Frame.cancel);
            throw const WraithException('Cancelled');
          }
          final chunk = await raf.read(min(kChunkSize, remaining));
          if (chunk.isEmpty) throw WraithException('"${f.name}" changed while sending');
          hasher.add(chunk);
          Uint8List? packed;
          if (tryCompress) {
            final z = _deflate.convert(chunk);
            if (z.length < chunk.length * 0.9) {
              packed = z is Uint8List ? z : Uint8List.fromList(z);
              misses = 0;
            } else if (++misses >= 3) {
              tryCompress = false; // incompressible content: stop trying
            }
          }
          if (packed != null) {
            job.compressedSaved += chunk.length - packed.length;
            await channel.send(Frame.dataZ, packed, false);
          } else {
            await channel.send(Frame.data, chunk, false);
          }
          remaining -= chunk.length;
          job.addProgress(chunk.length, clock);
          final cap = maxBytesPerSecond;
          if (cap > 0) {
            // Token-bucket pacing: never run ahead of the configured rate.
            paced += chunk.length;
            final aheadMs = paced * 1000 ~/ cap - clock.elapsedMilliseconds;
            if (aheadMs > 5) await Future<void>.delayed(Duration(milliseconds: aheadMs));
          }
        }
        await raf.close();
        raf = null;
        final digest = await hasher.close();
        sent.add(ReceiptFile(f.name, f.size, hexOf(digest)));
        await channel.sendJson(Frame.fileEnd, {'i': i, 'sha256': base64Encode(digest)});
      }

      await channel.send(Frame.done);
      job.update(() => job.status = TransferStatus.verifying);
      final result = (await channel.expect(Frame.result, timeout: _idleTimeout)).json();
      if (result['ok'] != true) throw const WraithException('Receiver could not verify the files');
      final receiptBody = result['receipt'];
      if (receiptBody is String && result['sig'] is String) {
        final receipt = DeliveryReceipt(
          body: receiptBody,
          signature: base64Decode(result['sig'] as String),
          signerKey: hs.peerIdentityKey,
        );
        await receipt.verifyFor(
          senderFingerprint: identity.fingerprint,
          receiverFingerprint: hs.peerFingerprint,
          transcript: hs.transcript,
          sent: sent,
          text: text,
        );
        job.receipt = receipt;
      }
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
      final ring = offer['ring'] == true && rawFiles.isEmpty && text == null;
      final speedTest = offer['speedtest'] == true && rawFiles.isEmpty && text == null;
      final manifestFor = rawFiles.isEmpty ? offer['syncManifest'] : null;
      final rawInvite = rawFiles.isEmpty ? offer['syncInvite'] : null;
      ({String id, String name})? invite;
      if (rawInvite is Map && rawInvite['id'] is String && rawInvite['name'] is String) {
        invite = (id: rawInvite['id'] as String, name: sanitizeFileName(rawInvite['name'] as String));
      }
      final syncId = rawFiles.isNotEmpty && offer['sync'] is String ? offer['sync'] as String : null;
      final search = rawFiles.isEmpty && text == null ? offer['search'] : null;
      final fetch = rawFiles.isEmpty && text == null ? offer['fetch'] : null;
      if (rawFiles.isEmpty && text == null && !ring && !speedTest && manifestFor is! String && invite == null &&
          search is! Map && fetch is! String) {
        throw const WraithException('Empty offer');
      }

      final files = <FileEntry>[];
      final segments = <List<String>>[];
      for (final f in rawFiles) {
        if (f is! Map) throw const WraithException('Invalid offer');
        final name = f['name'];
        final size = f['size'];
        if (name is! String || size is! int || size < 0) throw const WraithException('Invalid offer');
        final segs = sanitizeRelativePath(name);
        segments.add(segs);
        final mtime = f['mtime'];
        files.add(FileEntry(name: segs.join('/'), size: size, mtime: mtime is int ? mtime : null));
      }
      final previews = <int, Uint8List>{};
      final rawPreviews = offer['previews'];
      if (rawPreviews is Map) {
        for (final e in rawPreviews.entries.take(8)) {
          final i = int.tryParse('${e.key}');
          final v = e.value;
          if (i == null || i < 0 || i >= files.length || v is! String || v.length > 140000) continue;
          try {
            previews[i] = base64Decode(v);
          } catch (_) {}
        }
      }

      // Read the offer before declining a blocked device, so the reply is not
      // lost to a TCP reset caused by unread data.
      if (trust.isBlocked(hs.peerFingerprint)) {
        onRejected?.call(ip, 'blocked');
        await channel.send(Frame.decline);
        return;
      }

      // Search across devices: answer with matching files (no paths).
      if (search is Map) {
        final results = trust.isTrusted(hs.peerFingerprint)
            ? onSearch?.call(hs.peerFingerprint, Map<String, dynamic>.from(search))
            : null;
        if (results == null) {
          await channel.send(Frame.decline);
        } else {
          await channel.sendJson(Frame.accept, {'results': results.take(200).toList()});
        }
        return;
      }
      if (fetch is String) {
        final ok = trust.isTrusted(hs.peerFingerprint) &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(fetch) &&
            (onFetch?.call(hs.peerFingerprint, fetch) ?? false);
        await channel.send(ok ? Frame.accept : Frame.decline);
        return;
      }

      // Folder-sync manifest request: answer with this side's file list.
      if (manifestFor is String) {
        final folder = trust.isTrusted(hs.peerFingerprint) ? syncFolder?.call(manifestFor, hs.peerFingerprint) : null;
        if (folder == null) {
          await channel.send(Frame.decline);
        } else {
          await channel.sendJson(Frame.accept, {'manifest': encodeManifest(await buildManifest(folder))});
        }
        return;
      }
      Directory? syncRoot;
      if (syncId != null) {
        syncRoot = trust.isTrusted(hs.peerFingerprint) ? syncFolder?.call(syncId, hs.peerFingerprint) : null;
        if (syncRoot == null) {
          await channel.send(Frame.decline);
          return;
        }
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
        clipboard: offer['clip'] == true && text != null && rawFiles.isEmpty,
        ring: ring,
        chat: offer['chat'] == true && text != null && rawFiles.isEmpty,
        speedTest: speedTest,
        syncInvite: invite,
        syncId: syncId,
        previews: previews,
      );

      if (paired || syncRoot != null || (autoAccept?.call(request) ?? false)) {
        request.respond(true);
      } else if (speedTest) {
        request.respond(false); // speed tests never prompt
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

      // A sync invitation only needs the answer.
      if (invite != null) {
        await channel.send(Frame.accept);
        return;
      }

      // Speed test: count incoming bytes, discard them, report the rate.
      if (speedTest) {
        await channel.sendJson(Frame.accept, {});
        final clock = Stopwatch()..start();
        var bytes = 0;
        while (true) {
          final msg = await channel.receive(timeout: _idleTimeout);
          if (msg.type == Frame.data) {
            bytes += msg.body.length;
          } else if (msg.type == Frame.done) {
            await channel.sendJson(Frame.result, {'ok': true, 'bytes': bytes, 'ms': clock.elapsedMilliseconds});
            return;
          } else {
            throw const WraithException('Protocol violation (speed test)');
          }
        }
      }

      // Work out where every file goes and whether a partial copy from an
      // earlier, interrupted attempt by the same device can be resumed.
      final root = syncRoot ?? await (saveDirFor?.call(hs.peerName, hs.peerFingerprint) ?? saveDir());
      await root.create(recursive: true);
      final targets = <_Target>[];
      final resume = <String, int>{};
      for (var i = 0; i < files.length; i++) {
        final placer = syncRoot == null ? placeFile : null;
        final segs = placer == null
            ? segments[i]
            : [for (final s in placer(hs.peerName, hs.peerFingerprint, segments[i])) sanitizeFileName(s)];
        if (segs.isEmpty) throw const WraithException('Unsafe path rejected');
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
        ..sas = hs.sas
        ..clipboard = request.clipboard
        ..ring = request.ring
        ..peerAddress = ip;
      job = activeJob;
      onJob(activeJob);
      activeJob.syncId = syncId;
      activeJob.chat = request.chat;
      await channel.sendJson(Frame.accept, {
        'resume': resume,
        'caps': ['z'],
      });

      final clock = Stopwatch()..start();
      var index = -1;
      var written = 0;
      ChunkHasher? hasher;
      final received = <ReceiptFile>[];

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
          final h = ChunkHasher.create(files[i].size);
          hasher = h;
          await target.dir.create(recursive: true);
          partFile = target.part;
          if (target.offset > 0) {
            await for (final chunk in target.part.openRead(0, target.offset)) {
              h.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
            }
            raf = await target.part.open(mode: FileMode.append);
            activeJob.resumedBytes += target.offset;
            activeJob.addProgress(target.offset, clock);
          } else {
            raf = await target.part.open(mode: FileMode.write);
          }
        } else if (msg.type == Frame.data || msg.type == Frame.dataZ) {
          final out = raf;
          final h = hasher;
          if (out == null || h == null) throw const WraithException('Protocol violation (data outside file)');
          final body = msg.type == Frame.dataZ
              ? inflateBounded(msg.body, min(kChunkSize, files[index].size - written))
              : msg.body;
          if (msg.type == Frame.dataZ) activeJob.compressedSaved += body.length - msg.body.length;
          written += body.length;
          if (written > files[index].size) {
            throw const WraithException('Sender exceeded the announced file size');
          }
          await out.writeFrom(body);
          h.add(body);
          activeJob.addProgress(body.length, clock);
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
          final digest = await h.close();
          if (!constantTimeEquals(digest, expected)) {
            throw WraithException('SHA-256 mismatch on "${files[index].name}" — file discarded');
          }
          final File dest;
          if (syncRoot != null) {
            // Folder sync: replace in place, keeping the old version in the archive.
            dest = File(p.join(targets[index].dir.path, targets[index].baseName));
            // Journaled: a crash between "archive" and "rename" is rolled back
            // on the next start (Smart Recovery), so the old copy is never lost.
            final archivePath = archivePathFor(syncRoot, dest);
            final op = journal?.begin('replace', {'dest': dest.path, 'archived': archivePath});
            await archiveExisting(syncRoot, dest, to: archivePath);
            await part.rename(dest.path);
            if (op != null) journal!.end(op);
            final mtime = files[index].mtime;
            if (mtime != null) {
              try {
                await dest.setLastModified(DateTime.fromMillisecondsSinceEpoch(mtime));
              } catch (_) {}
            }
          } else {
            dest = await uniqueFile(targets[index].dir, targets[index].baseName);
            await part.rename(dest.path);
          }
          partFile = null;
          hasher = null;
          received.add(ReceiptFile(files[index].name, files[index].size, hexOf(digest)));
          activeJob.update(() {
            activeJob.savedPaths.add(dest.path);
            activeJob.savedHashes[dest.path] = hexOf(digest);
            activeJob.verifiedFiles++;
          });
        } else if (msg.type == Frame.done) {
          if (index != files.length - 1 || raf != null) {
            throw const WraithException('Transfer ended early');
          }
          if (activeJob.ring) {
            await channel.sendJson(Frame.result, {'ok': true, 'verified': 0});
            activeJob.finish(TransferStatus.done);
            return;
          }
          final receipt = await DeliveryReceipt.create(
            receiver: identity,
            senderFingerprint: hs.peerFingerprint,
            senderName: hs.peerName,
            files: received,
            transcript: hs.transcript,
            text: text,
          );
          activeJob.receipt = receipt;
          await channel.sendJson(Frame.result, {
            'ok': true,
            'verified': files.length,
            'receipt': receipt.body,
            'sig': base64Encode(receipt.signature),
          });
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

  // ─────────────────────────── Special sessions ───────────────────────────

  Future<(Socket, Handshake)> _openSecure(Peer peer) async {
    final socket = await _connect(peer);
    socket.setOption(SocketOption.tcpNoDelay, true);
    try {
      final hs = await wraithHandshake(socket: socket, reader: FrameReader(socket), me: identity, initiator: true);
      if (!peer.manual && hs.peerFingerprint != peer.id) {
        throw const WraithException('Fingerprint mismatch — possible spoofing');
      }
      if (trust.isBlocked(hs.peerFingerprint)) throw const WraithException('This device is on your block list');
      return (socket, hs);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  /// Measures real SUDOSEND throughput to [peer] (encryption included) by
  /// streaming random data for [duration]. Returns bytes/second as measured
  /// by the receiver. The receiver only accepts from trusted devices.
  Future<double> speedTest(Peer peer, {Duration duration = const Duration(seconds: 6)}) async {
    final (_, hs) = await _openSecure(peer);
    final channel = hs.channel;
    try {
      await channel.sendJson(Frame.offer, {'files': [], 'speedtest': true});
      final reply = await channel.receive(timeout: const Duration(seconds: 15));
      if (reply.type != Frame.accept) {
        throw const WraithException('Speed test declined — it works between trusted devices only');
      }
      final rng = Random();
      final block = Uint8List.fromList(List<int>.generate(kChunkSize, (_) => rng.nextInt(256)));
      final clock = Stopwatch()..start();
      while (clock.elapsed < duration) {
        await channel.send(Frame.data, block, false);
      }
      await channel.send(Frame.done);
      final result = (await channel.expect(Frame.result, timeout: const Duration(seconds: 30))).json();
      final bytes = result['bytes'] as int;
      final ms = max(1, result['ms'] as int);
      return bytes * 1000 / ms;
    } finally {
      await channel.close();
    }
  }

  /// Asks [peer] for the manifest of sync pair [syncId].
  Future<List<ManifestEntry>> fetchManifest(Peer peer, String syncId) async {
    final (_, hs) = await _openSecure(peer);
    final channel = hs.channel;
    try {
      await channel.sendJson(Frame.offer, {'files': [], 'syncManifest': syncId});
      final reply = await channel.receive(timeout: const Duration(seconds: 60));
      if (reply.type != Frame.accept) throw const WraithException('The other device has no such sync folder');
      return decodeManifest(reply.json()['manifest'] as String);
    } finally {
      await channel.close();
    }
  }

  /// Searches the received files of [peer] (a trusted device that allows it).
  /// Returns null if the device refused.
  Future<List<Map<String, dynamic>>?> searchRemote(Peer peer, Map<String, Object?> query) async {
    final (_, hs) = await _openSecure(peer);
    final channel = hs.channel;
    try {
      await channel.sendJson(Frame.offer, {'files': [], 'search': query});
      final reply = await channel.receive(timeout: const Duration(seconds: 15));
      if (reply.type != Frame.accept) return null;
      final raw = reply.json()['results'];
      return [
        if (raw is List)
          for (final r in raw.take(200))
            if (r is Map) Map<String, dynamic>.from(r),
      ];
    } finally {
      await channel.close();
    }
  }

  /// Asks [peer] to send this device the file with [sha256].
  Future<bool> requestFetch(Peer peer, String sha256) async {
    final (_, hs) = await _openSecure(peer);
    final channel = hs.channel;
    try {
      await channel.sendJson(Frame.offer, {'files': [], 'fetch': sha256});
      final reply = await channel.receive(timeout: const Duration(seconds: 15));
      return reply.type == Frame.accept;
    } finally {
      await channel.close();
    }
  }

  /// Invites [peer] to sync a folder. Returns true if the user there accepted.
  Future<bool> sendSyncInvite(Peer peer, String syncId, String name) async {
    final (_, hs) = await _openSecure(peer);
    final channel = hs.channel;
    try {
      await channel.sendJson(Frame.offer, {
        'files': [],
        'syncInvite': {'id': syncId, 'name': name},
      });
      final reply = await channel.receive(timeout: _approvalTimeout + const Duration(seconds: 10));
      return reply.type == Frame.accept;
    } finally {
      await channel.close();
    }
  }
}

final ZLibEncoder _deflate = ZLibEncoder(raw: true, level: 1);

const Set<String> _incompressible = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'avif', //
  'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v', 'mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac',
  'zip', 'gz', 'tgz', 'xz', 'bz2', '7z', 'rar', 'zst', 'lz4', 'apk', 'aab', 'ipa', 'jar',
  'docx', 'xlsx', 'pptx', 'odt', 'epub', 'pdf', 'iso', 'dmg', 'deb', 'rpm',
};

/// Cheap first filter for smart compression (the real test is per chunk).
bool worthCompressing(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 || !_incompressible.contains(name.substring(dot + 1).toLowerCase());
}

/// Inflates raw-deflate [data], refusing to produce more than [maxOut]
/// bytes (protection against decompression bombs).
Uint8List inflateBounded(Uint8List data, int maxOut) {
  final sink = _BoundedSink(maxOut);
  final conv = ZLibDecoder(raw: true).startChunkedConversion(sink);
  for (var o = 0; o < data.length; o += 8192) {
    conv.add(Uint8List.sublistView(data, o, min(o + 8192, data.length)));
  }
  conv.close();
  return sink.takeBytes();
}

class _BoundedSink implements Sink<List<int>> {
  _BoundedSink(this.max);
  final int max;
  final BytesBuilder _b = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    if (_b.length + data.length > max) throw const WraithException('Compressed data expands too much');
    _b.add(data);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _b.takeBytes();
}
