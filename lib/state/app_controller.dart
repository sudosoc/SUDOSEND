import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wraith_core/discovery.dart';
import 'package:wraith_core/identity.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/pairing.dart';
import 'package:wraith_core/receipt.dart';
import 'package:wraith_core/sync.dart';
import 'package:wraith_core/transfer.dart';
import 'package:wraith_core/util.dart';
import 'package:wraith_core/vault_windows.dart';
import 'package:wraith_core/web_share.dart';
import 'package:wraith_core/wraith.dart';

import '../app/scope.dart' show kAppVersion;
import '../app/strings.dart';
import '../platform/desktop.dart';
import '../platform/native_bridge.dart';
import 'chat.dart';
import 'history.dart';
import 'outbox.dart';
import 'previews.dart';
import 'settings.dart';
import 'updater.dart';

class AppController extends ChangeNotifier {
  AppController({this.initialArgs = const []});

  final List<String> initialArgs;
  final SettingsController settings = SettingsController();
  final NativeBridge _native = NativeBridge.instance;

  late DeviceIdentity identity;
  late TrustStore trust;
  late HistoryStore history;
  late ChatStore chat;
  late Discovery _discovery;
  late Directory _support;
  late TransferEngine _engine;

  bool ready = false;
  String? startupError;
  List<InternetAddress> localAddresses = const [];
  Directory? saveDir;
  int tab = 0;
  int rejectedConnections = 0;
  bool foreground = true;

  /// Jobs of this session, newest first (finished ones are also in [history]).
  final List<TransferJob> jobs = [];
  final List<FileEntry> selected = [];

  /// A text/clipboard message queued for sending (instead of files).
  String? selectedText;

  final Map<String, StreamSubscription<void>> _jobSubs = {};
  final Map<String, IncomingRequest> _pendingRequests = {};
  final StreamController<IncomingRequest> _incoming = StreamController<IncomingRequest>.broadcast();
  final StreamController<String> _messages = StreamController<String>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  AppLifecycleListener? _lifecycle;

  PairingInfo? _pairing;
  DateTime _pairingExpires = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<IncomingRequest> get incoming => _incoming.stream;

  /// Short user-facing messages (snackbars).
  Stream<String> get messages => _messages.stream;

  List<Peer> get peers => ready ? _discovery.peers : const [];
  int get port => ready ? _engine.port : kTransferPort;
  bool get hasSelection => selected.isNotEmpty || selectedText != null;
  int get selectedBytes => selected.fold<int>(0, (a, f) => a + f.size);
  int get activeJobs => jobs.where((j) => j.isActive).length;
  String t(String key, [Map<String, Object?> args = const {}]) => tr(settings.lang, key, args);

  /// History entries from earlier sessions (this session's jobs are shown live).
  List<HistoryEntry> get earlierHistory {
    final live = {for (final j in jobs) j.id};
    return history.entries.where((e) => !live.contains(e.id)).toList();
  }

  // ─────────────────────────── Startup ───────────────────────────

  Future<void> init() async {
    try {
      await _native.acquireMulticastLock();
      final support = await getApplicationSupportDirectory();
      _support = support;
      await settings.load(support);
      SeedVault? vault;
      if (Platform.isAndroid) {
        vault = AndroidKeystoreVault();
      } else if (DpapiVault.supported) {
        vault = DpapiVault();
      }
      identity = await DeviceIdentity.loadOrCreate(support, vault: vault);
      trust = await TrustStore.load(support);
      history = await HistoryStore.load(support);
      chat = await ChatStore.load(support);
      outbox = await OutboxStore.load(support);
      saveDir = await _resolveSaveDir();

      _engine = TransferEngine(
        identity: identity,
        trust: trust,
        saveDir: () async => saveDir!,
        saveDirFor: (name, fp) async => settings.senderFolders
            ? Directory(p.join(saveDir!.path, sanitizeFileName(name)))
            : saveDir!,
        autoAccept: (r) {
          if (!r.trusted) return false;
          if (r.ring) return settings.allowRing;
          if (r.clipboard) return settings.clipboardSync;
          if (r.speedTest) return settings.allowSpeedTest;
          if (r.chat && settings.chat) return true;
          if (r.syncInvite != null) return false; // always asks: a folder must be chosen
          return settings.autoAcceptTrusted;
        },
        onIncoming: _onIncoming,
        onJob: _addJob,
        onRejected: (address, reason) {
          rejectedConnections++;
          notifyListeners();
        },
      );
      _engine.syncFolder = _syncFolderFor;
      await _engine.start();

      _discovery = Discovery(identity: identity, transferPort: _engine.port, onChanged: _onPeersChanged)
        ..stealth = settings.stealth;
      await _discovery.start();
      await _refreshAddresses();

      _lifecycle = AppLifecycleListener(onStateChange: (state) {
        foreground = state == AppLifecycleState.resumed;
        if (foreground) {
          unawaited(_refreshAddresses().then((_) => notifyListeners()));
          // Mobile OSes only allow clipboard reads in the foreground.
          if (!isDesktop && settings.clipboardSync) unawaited(pollClipboard());
        }
      });
      foreground = WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

      _subs.add(_native.shares.listen((_) => _importShare()));
      _subs.add(_native.notificationActions.listen(_onNotificationAction));
      _subs.add(_native.hotspotStopped.listen((_) {
        hotspot = null;
        notifyListeners();
      }));
      settings.addListener(_applySettings);
      _outboxTimer = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_flushOutbox()));
      _subs.add(_native.ringStopped.listen((_) => _rings.add('')));
      if (isDesktop) unawaited(SingleInstance.listen((args) => addPaths(args)));

      if (Platform.isAndroid && !settings.effectsChosen && await _native.isLowRam()) {
        settings.effects = 'lite';
      }
      _applySettings();
      ready = true;
      notifyListeners();

      if (identity.regenerated) _messages.add(t('identity_regenerated'));
      if (Platform.isAndroid) {
        if (settings.notifications) await _native.requestPermission('notifications');
        await _importShare();
        _updateService();
      }
      if (initialArgs.isNotEmpty) await addPaths(initialArgs);
      if (settings.autoUpdateCheck && !Platform.isIOS) {
        unawaited(Future<void>.delayed(const Duration(seconds: 8), () => checkForUpdates(silent: true)));
      }
    } catch (e) {
      startupError = describeError(e);
      notifyListeners();
    }
  }

  void setTab(int i) {
    if (tab == i) return;
    tab = i;
    notifyListeners();
  }

  // ─────────────────────────── Incoming ───────────────────────────

  void _onIncoming(IncomingRequest r) {
    // Clipboard pushes never prompt: accepted silently from trusted devices
    // when sync is on (see autoAccept), declined otherwise.
    if (r.clipboard || r.ring || r.speedTest) {
      r.respond(false);
      return;
    }
    if (r.syncInvite != null && !syncSupported) {
      r.respond(false);
      return;
    }
    _pendingRequests[r.id] = r;
    tab = 1;
    notifyListeners();
    _incoming.add(r);
    final what = r.syncInvite != null
        ? t('sync_invite_notif', {'name': r.syncInvite!.name})
        : r.text != null
        ? t('notif_incoming_text')
        : t('notif_incoming_files', {'n': r.files.length, 'size': formatBytes(r.totalBytes)});
    final title = t('notif_incoming_title', {'name': r.peerName});
    final body = r.trusted ? '$what · ${t('trusted_device')}' : '$what · ${t('notif_code', {'code': formatSas(r.sas)})}';
    if (settings.notifications) {
      if (Platform.isAndroid) {
        unawaited(_native.notifyIncoming(r.id, title, body, accept: t('accept'), decline: t('decline')));
      } else if (!foreground) {
        unawaited(desktopNotify(title, body));
      }
    }
    unawaited(r.decision.then((_) {
      _pendingRequests.remove(r.id);
      unawaited(_native.cancelNotification(r.id));
    }));
  }

  void _onNotificationAction(NotificationAction a) {
    final request = _pendingRequests[a.id];
    switch (a.action) {
      case 'accept':
        request?.respond(true);
        setTab(2);
      case 'decline':
        request?.respond(false);
      case 'open':
        setTab(request != null ? 1 : 2);
    }
  }

  // ─────────────────────────── Jobs ───────────────────────────

  void _addJob(TransferJob job) {
    if (job.syncId != null) {
      _watchSyncJob(job);
      return;
    }
    if (job.chat && settings.chat) {
      _watchChatJob(job);
      return;
    }
    if (job.ring) {
      var finished = false;
      job.changes.listen((_) {
        if (finished || job.isActive) return;
        finished = true;
        if (job.direction == TransferDirection.incoming && job.status == TransferStatus.done) {
          _startRinging(job.peerName);
        }
        job.dispose();
      });
      return;
    }
    if (job.clipboard) {
      // Silent: not shown in the list or kept in history.
      var finished = false;
      job.changes.listen((_) {
        if (finished || job.isActive) return;
        finished = true;
        if (job.direction == TransferDirection.incoming && job.status == TransferStatus.done) {
          _lastRemoteClip = job.text;
          _lastClip = job.text;
          unawaited(Clipboard.setData(ClipboardData(text: job.text!)));
          if (foreground) _messages.add(t('clip_received', {'name': job.peerName}));
        }
        job.dispose();
      });
      return;
    }
    jobs.insert(0, job);
    var wasActive = job.isActive;
    _jobSubs[job.id] = job.changes.listen((_) {
      _updateService();
      if (wasActive && !job.isActive) {
        wasActive = false;
        _onJobFinished(job);
      }
    });
    _updateService();
    notifyListeners();
  }

  void _onJobFinished(TransferJob job) {
    unawaited(_record(job));
    if (job.status == TransferStatus.done &&
        job.isText &&
        job.direction == TransferDirection.incoming &&
        settings.autoCopyText) {
      unawaited(Clipboard.setData(ClipboardData(text: job.text!)));
      _messages.add(t('copied_auto', {'name': job.peerName}));
    }
    notifyListeners();
    if (!settings.notifications || job.status == TransferStatus.cancelled) return;
    final incoming = job.direction == TransferDirection.incoming;
    final String title;
    switch (job.status) {
      case TransferStatus.done:
        title = incoming
            ? (job.isText ? t('notif_text_received', {'name': job.peerName}) : t('notif_received', {'n': job.files.length, 'name': job.peerName}))
            : t('notif_sent', {'name': job.peerName});
      case TransferStatus.declined:
        title = t('notif_declined', {'name': job.peerName});
      default:
        title = t('notif_failed', {'name': job.peerName});
    }
    final body = job.error ?? (job.isText ? (job.text ?? '') : formatBytes(job.totalBytes));
    if (Platform.isAndroid) {
      if (!foreground) unawaited(_native.notify(job.id, title, body.length > 200 ? '${body.substring(0, 200)}…' : body));
    } else if (!foreground) {
      unawaited(desktopNotify(title, body));
    }
  }

  Future<void> _record(TransferJob job) async {
    String? receiptPath;
    final receipt = job.receipt;
    if (receipt != null) {
      try {
        final dir = await Directory(p.join(_support.path, 'receipts')).create(recursive: true);
        final file = File(p.join(dir.path, '${job.id}.json'));
        await file.writeAsString(receipt.toPrettyJson());
        receiptPath = file.path;
      } catch (_) {}
    }
    await history.add(HistoryEntry.fromJob(job, receiptPath: receiptPath));
    notifyListeners();
  }

  Future<DeliveryReceipt?> loadReceipt(String path) async {
    try {
      return DeliveryReceipt.parse(await File(path).readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Lets the user save a file (receipt, history export). Returns the path or null.
  Future<String?> exportText(String fileName, String content) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final path = await FilePicker.platform.saveFile(fileName: fileName, bytes: bytes);
    if (path == null) return null;
    if (isDesktop) {
      final f = File(path);
      if (!await f.exists() || await f.length() == 0) await f.writeAsBytes(bytes);
    }
    return path;
  }

  Future<String?> exportReceipt(DeliveryReceipt receipt) {
    final d = receipt.data;
    final when = (d['completed'] as String? ?? '').split('.').first.replaceAll(':', '-');
    return exportText('sudosend-receipt-$when.json', receipt.toPrettyJson());
  }

  Future<String?> exportHistory() => exportText(
        'sudosend-history-${DateTime.now().toIso8601String().split('T').first}.json',
        history.exportJson(),
      );

  Future<bool> openUrl(String url) async {
    final scheme = Uri.tryParse(url)?.scheme;
    if (scheme != 'http' && scheme != 'https') return false;
    if (Platform.isAndroid) return _native.openUrl(url);
    return openWithSystem(url);
  }

  String _lastService = '';
  DateTime _lastServiceAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Keeps the Android foreground service in step with transfer activity.
  void _updateService() {
    if (!Platform.isAndroid || !ready) return;
    final active = jobs.where((j) => j.isActive).toList();
    String mode;
    String text;
    var progress = -1;
    if (active.isEmpty && (webShare?.running ?? false)) {
      mode = 'active';
      text = t('svc_web');
    } else if (active.isEmpty && hotspot != null) {
      mode = 'active';
      text = t('svc_hotspot', {'ssid': hotspot!.ssid});
    } else if (active.isNotEmpty) {
      mode = 'active';
      final total = active.fold<int>(0, (a, j) => a + j.totalBytes);
      final done = active.fold<int>(0, (a, j) => a + j.doneBytes);
      final speed = active.fold<double>(0, (a, j) => a + j.speed);
      progress = total == 0 ? -1 : (done * 100 ~/ total);
      final sending = active.where((j) => j.direction == TransferDirection.outgoing).length;
      final receiving = active.length - sending;
      text = [
        if (sending > 0) t('svc_sending', {'n': sending}),
        if (receiving > 0) t('svc_receiving', {'n': receiving}),
        if (progress >= 0) '$progress%',
        if (speed > 0) formatSpeed(speed),
      ].join(' · ');
    } else if (settings.backgroundReceive) {
      mode = 'idle';
      text = t('svc_ready', {'name': identity.name});
    } else {
      mode = 'off';
      text = '';
    }
    final key = '$mode|$text|$progress';
    final now = DateTime.now();
    final modeChanged = !_lastService.startsWith('$mode|');
    if (key == _lastService || (!modeChanged && now.difference(_lastServiceAt) < const Duration(milliseconds: 900))) return;
    _lastService = key;
    _lastServiceAt = now;
    unawaited(_native.service(mode, title: 'SUDOSEND', text: text, progress: progress));
  }

  void clearFinished() {
    jobs.removeWhere((j) {
      final finished = !j.isActive;
      if (finished) {
        _jobSubs.remove(j.id)?.cancel();
        j.dispose();
      }
      return finished;
    });
    notifyListeners();
  }

  Future<void> clearHistory() async {
    clearFinished();
    await history.clear();
    notifyListeners();
  }

  // ─────────────────────────── Selection ───────────────────────────

  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (result == null) return;
    for (final f in result.files) {
      final path = f.path;
      if (path == null || selected.any((s) => s.path == path)) continue;
      selected.add(FileEntry(name: f.name, size: await File(path).length(), path: path));
    }
    selectedText = null;
    notifyListeners();
  }

  /// Returns an error message, or null on success.
  Future<String?> pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return null;
    return addPaths([path]);
  }

  /// Adds files and folders (drag & drop, "Send to", command-line arguments).
  /// Returns an error message, or null on success.
  Future<String?> addPaths(List<String> paths) async {
    var added = 0;
    String? error;
    for (final raw in paths) {
      if (raw.startsWith('-')) continue;
      try {
        final type = await FileSystemEntity.type(raw);
        if (type == FileSystemEntityType.file) {
          final f = File(raw);
          if (selected.any((s) => s.path == f.path)) continue;
          selected.add(FileEntry(name: p.basename(f.path), size: await f.length(), path: f.path));
          added++;
        } else if (type == FileSystemEntityType.directory) {
          final root = Directory(raw);
          final rootName = p.basename(p.normalize(root.path));
          await for (final entity in root.list(recursive: true, followLinks: false)) {
            if (entity is! File || selected.any((s) => s.path == entity.path)) continue;
            final rel = p.relative(entity.path, from: root.path).split(p.separator).join('/');
            selected.add(FileEntry(name: '$rootName/$rel', size: await entity.length(), path: entity.path));
            added++;
          }
        }
      } on FileSystemException catch (e) {
        error = t('err_folder', {'reason': e.osError?.message ?? e.message});
      }
    }
    if (added > 0) {
      selectedText = null;
      tab = 0;
    }
    notifyListeners();
    return error ?? (added == 0 && paths.isNotEmpty ? t('err_no_files') : null);
  }

  Future<void> _importShare() async {
    final share = await _native.takeShare();
    if (share == null) return;
    if (share.files.isNotEmpty) {
      selected
        ..clear()
        ..addAll([for (final f in share.files) FileEntry(name: f.name, size: f.size, path: f.path)]);
      selectedText = null;
    } else {
      selected.clear();
      selectedText = share.text;
    }
    tab = 0;
    notifyListeners();
    _messages.add(t('share_ready'));
  }

  void setText(String? text) {
    final trimmed = text?.trim();
    selectedText = (trimmed == null || trimmed.isEmpty) ? null : text;
    if (selectedText != null) selected.clear();
    notifyListeners();
  }

  void removeSelected(FileEntry f) {
    selected.remove(f);
    notifyListeners();
  }

  void clearSelected() {
    selected.clear();
    selectedText = null;
    notifyListeners();
  }

  // ─────────────────────────── Sending ───────────────────────────

  Future<void> sendTo(Peer peer, {String? pairToken}) async {
    if (!hasSelection) return;
    final files = List<FileEntry>.of(selected);
    final text = selectedText;
    selected.clear();
    selectedText = null;
    tab = 2;
    notifyListeners();
    final previews = await _previewsFor(files);
    await _sendWithRetry(peer, files, text: text, pairToken: pairToken, previews: previews);
    notifyListeners();
  }

  /// Sends the current selection to several devices in parallel.
  Future<void> sendToMany(List<Peer> peers) async {
    if (!hasSelection || peers.isEmpty) return;
    final files = List<FileEntry>.of(selected);
    final text = selectedText;
    selected.clear();
    selectedText = null;
    tab = 2;
    notifyListeners();
    final previews = await _previewsFor(files);
    await Future.wait([for (final peer in peers) _sendWithRetry(peer, files, text: text, previews: previews)]);
    notifyListeners();
  }

  /// Accepts an IP ("192.168.1.20", "192.168.1.20:47824") or a pairing link.
  /// Returns an error message, or null when the transfer was started.
  Future<String?> sendToTarget(String input) async {
    final text = input.trim();
    if (!hasSelection) return t('err_pick_first');
    final pairing = PairingInfo.tryParse(text);
    if (pairing != null) {
      if (pairing.fingerprint == identity.fingerprint) return t('err_self');
      unawaited(sendTo(pairing.toPeer(), pairToken: pairing.token));
      return null;
    }
    if (text.startsWith('sudosend:')) return t('err_bad_link');
    final idx = text.lastIndexOf(':');
    final host = idx > 0 ? text.substring(0, idx) : text;
    final port = idx > 0 ? int.tryParse(text.substring(idx + 1)) : kTransferPort;
    final address = InternetAddress.tryParse(host);
    if (address == null || address.type != InternetAddressType.IPv4) return t('err_ip');
    if (port == null || port < 1 || port > 65535) return t('err_port');
    unawaited(sendTo(Peer.manual(address, port)));
    return null;
  }

  // ─────────────────────────── Pairing ───────────────────────────

  /// QR / link for the Receive tab. Rotates every 10 minutes and after use.
  PairingInfo? get pairing {
    if (!ready || localAddresses.isEmpty) return null;
    final current = _pairing;
    if (current == null || DateTime.now().isAfter(_pairingExpires) || !_engineHasToken(current.token)) {
      refreshPairing(notify: false);
    }
    return _pairing;
  }

  bool _engineHasToken(String? token) => token != null && _engine.isPairingTokenValid(token);

  void refreshPairing({bool notify = true}) {
    final old = _pairing?.token;
    if (old != null) _engine.revokePairingToken(old);
    const ttl = Duration(minutes: 10);
    final token = _engine.createPairingToken(ttl: ttl);
    _pairing = PairingInfo(
      name: identity.name,
      fingerprint: identity.fingerprint,
      addresses: localAddresses,
      port: _engine.port,
      token: token,
    );
    _pairingExpires = DateTime.now().add(ttl - const Duration(seconds: 30));
    if (notify) notifyListeners();
  }

  // ─────────────────────────── Files ───────────────────────────

  Future<bool> openFile(String path) async {
    if (Platform.isAndroid) return _native.openFile(path);
    return openWithSystem(path);
  }

  Future<bool> reveal(String path) => revealInFolder(path);

  // ─────────────────────────── Settings ───────────────────────────

  // ─────────────────────────── Effects & clipboard ───────────────────────────

  Timer? _clipTimer;
  String? _lastClip;
  String? _lastRemoteClip;

  void _applySettings() {
    TransferJob.progressIntervalMs = settings.reduceEffects ? 300 : 150;
    TransferEngine.maxBytesPerSecond = settings.uploadLimit * 1024 * 1024;
    TransferEngine.compression = settings.compression;
    if (!settings.chat && tab == 3) {
      tab = 0;
      notifyListeners();
    }
    final wantSync = settings.folderSync && settings.syncPairs.any((s) => s.enabled);
    if (wantSync && _syncTimer == null) {
      _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => unawaited(syncNow()));
      unawaited(Future<void>.delayed(const Duration(seconds: 5), syncNow));
    } else if (!wantSync && _syncTimer != null) {
      _syncTimer!.cancel();
      _syncTimer = null;
    }
    if (!settings.webShare && webShare != null) unawaited(stopWebShare());
    final wantHot = settings.hotFolders && isDesktop;
    if (wantHot && _hotTimer == null) {
      _hotTimer = Timer.periodic(const Duration(seconds: 4), (_) => unawaited(_scanHotFolders()));
      unawaited(_scanHotFolders());
    } else if (!wantHot && _hotTimer != null) {
      _hotTimer!.cancel();
      _hotTimer = null;
    }
    final wantPolling = settings.clipboardSync && isDesktop;
    if (wantPolling && _clipTimer == null) {
      unawaited(Clipboard.getData(Clipboard.kTextPlain).then((d) => _lastClip = d?.text));
      _clipTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => unawaited(pollClipboard()));
    } else if (!wantPolling && _clipTimer != null) {
      _clipTimer!.cancel();
      _clipTimer = null;
    }
  }

  List<Peer> get trustedOnline => peers.where((p) => trust.isTrusted(p.id)).toList();

  /// Pushes the clipboard to trusted devices if it changed. Returns how many
  /// devices it was sent to. [force] sends even if unchanged (manual button).
  Future<int> pollClipboard({bool force = false}) async {
    if (!ready) return 0;
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {
      return 0;
    }
    if (text == null || text.trim().isEmpty || text.length > kMaxTextLength) return 0;
    if (!force && (text == _lastClip || text == _lastRemoteClip)) {
      _lastClip = text;
      return 0;
    }
    _lastClip = text;
    final targets = trustedOnline;
    for (final peer in targets) {
      unawaited(_engine.send(peer, const [], text: text, clipboard: true));
    }
    return targets.length;
  }

  // ─────────────────────────── Browser share ───────────────────────────

  WebShare? webShare;
  final List<WebShareEvent> webEvents = [];

  List<String> get webUrls => webShare == null ? const [] : webShare!.urls(localAddresses);

  /// Shares the current selection (if [withSelection]) with browsers, and
  /// optionally lets browsers upload files to this device.
  Future<String?> startWebShare({
    required bool upload,
    required bool withSelection,
    String? pin,
    Duration ttl = const Duration(minutes: 30),
    int? maxDownloads,
  }) async {
    await stopWebShare();
    final files = withSelection ? List<FileEntry>.of(selected) : <FileEntry>[];
    final text = withSelection ? selectedText : null;
    if (files.isEmpty && text == null && !upload) return t('err_pick_first');
    webEvents.clear();
    final share = WebShare(
      files: files,
      text: text,
      allowUpload: upload,
      deviceName: identity.name,
      saveDir: () async => settings.senderFolders ? Directory(p.join(saveDir!.path, 'Browser')) : saveDir!,
      onEvent: _onWebEvent,
      pin: pin,
      ttl: ttl,
      maxDownloads: maxDownloads,
      onStopped: () {
        webShare = null;
        _lastService = '';
        _updateService();
        notifyListeners();
      },
    );
    try {
      await share.start();
    } catch (e) {
      return describeError(e);
    }
    webShare = share;
    _lastService = '';
    _updateService();
    notifyListeners();
    return null;
  }

  void _onWebEvent(WebShareEvent e) {
    webEvents.insert(0, e);
    if (webEvents.length > 200) webEvents.removeLast();
    if (e.kind == 'upload') {
      unawaited(history.add(HistoryEntry(
        id: 'web-${e.at.microsecondsSinceEpoch}',
        direction: TransferDirection.incoming,
        peerName: 'Browser ${e.address}',
        peerPlatform: 'web',
        fileCount: 1,
        totalBytes: e.size,
        status: TransferStatus.done,
        isText: false,
        at: e.at,
        firstName: e.name,
        savedPaths: [if (e.path != null) e.path!],
      )));
      if (settings.notifications && !foreground) {
        final title = t('notif_received', {'n': 1, 'name': 'Browser ${e.address}'});
        if (Platform.isAndroid) {
          unawaited(_native.notify('web-${e.at.microsecondsSinceEpoch}', title, e.name));
        } else {
          unawaited(desktopNotify(title, e.name));
        }
      }
    }
    notifyListeners();
  }

  Future<void> stopWebShare() async {
    final share = webShare;
    webShare = null;
    await share?.stop();
    notifyListeners();
  }

  // ─────────────────────────── Hotspot (Android) ───────────────────────────

  ({String ssid, String password})? hotspot;

  /// Returns an error message, or null when the hotspot is up.
  Future<String?> startHotspot() async {
    if (!await _native.requestPermission('hotspot')) return t('err_hotspot_permission');
    try {
      hotspot = await _native.startHotspot();
    } catch (e) {
      return '$e';
    }
    _lastService = '';
    _updateService();
    notifyListeners();
    // The hotspot interface needs a moment to get its address.
    for (final delay in const [1, 3, 6]) {
      unawaited(Future<void>.delayed(Duration(seconds: delay), () async {
        await _refreshAddresses();
        await _discovery.rescan();
        notifyListeners();
      }));
    }
    return null;
  }

  Future<void> stopHotspot() async {
    await _native.stopHotspot();
    hotspot = null;
    _lastService = '';
    _updateService();
    notifyListeners();
  }

  // ─────────────────────────── Retry & outbox ───────────────────────────

  late OutboxStore outbox;
  final Set<String> _outboxInflight = {};
  Timer? _outboxTimer;
  Timer? _hotTimer;

  static bool _retryable(TransferJob job) {
    if (job.status != TransferStatus.failed) return false;
    final e = job.error ?? '';
    return e.startsWith('Connection') || e.startsWith('Timed out');
  }

  /// Sends with automatic retries (3 attempts) for dropped connections; each
  /// retry resumes where the last one stopped.
  Future<TransferJob> _sendWithRetry(Peer peer, List<FileEntry> files,
      {String? text, String? pairToken, Map<int, Uint8List>? previews}) async {
    var target = peer;
    var job = await _engine.send(target, files, text: text, pairToken: pairToken, previews: previews);
    for (final wait in const [Duration(seconds: 3), Duration(seconds: 10)]) {
      if (!_retryable(job)) break;
      await Future<void>.delayed(wait);
      if (!peer.manual) {
        // The device may have changed address (e.g. Wi-Fi reconnect).
        target = peers.firstWhere((p) => p.id == peer.id, orElse: () => target);
      }
      job = await _engine.send(target, files, text: text, pairToken: pairToken, previews: previews);
    }
    return job;
  }

  void _onPeersChanged() {
    notifyListeners();
    unawaited(_flushOutbox());
    // A sync partner just showed up: sync right away instead of waiting.
    final online = {for (final p in peers) p.id};
    final fresh = online.difference(_seenPeers);
    _seenPeers = online;
    if (fresh.isNotEmpty && settings.folderSync && settings.syncPairs.any((s) => s.enabled && fresh.contains(s.fingerprint))) {
      unawaited(syncNow());
    }
  }

  Set<String> _seenPeers = {};

  /// Trusted devices that are not currently visible (for "send when online").
  List<KnownDevice> get trustedOffline {
    final online = {for (final p in peers) p.id};
    return trust.all.where((d) => !online.contains(d.fingerprint)).toList();
  }

  /// Queues the current selection for a trusted device that is offline.
  Future<void> enqueueFor(KnownDevice device) async {
    if (!hasSelection) return;
    await outbox.add(OutboxItem(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      fingerprint: device.fingerprint,
      peerName: device.name,
      files: List.of(selected),
      text: selectedText,
      created: DateTime.now(),
    ));
    selected.clear();
    selectedText = null;
    _messages.add(t('queued', {'name': device.name}));
    notifyListeners();
    unawaited(_flushOutbox());
  }

  Future<void> removeOutbox(String id) async {
    await outbox.remove(id);
    notifyListeners();
  }

  Future<void> _flushOutbox() async {
    if (!ready) return;
    for (final item in List.of(outbox.items)) {
      if (_outboxInflight.contains(item.id)) continue;
      final peer = peers.where((p) => p.id == item.fingerprint).firstOrNull;
      if (peer == null) continue;
      final files = item.files.where((f) => f.path != null && File(f.path!).existsSync()).toList();
      if (files.isEmpty && item.text == null) {
        await outbox.remove(item.id);
        continue;
      }
      _outboxInflight.add(item.id);
      unawaited(() async {
        final job = await _sendWithRetry(peer, files, text: item.text);
        _outboxInflight.remove(item.id);
        if (job.status == TransferStatus.done) {
          await outbox.remove(item.id);
          await _archiveHot(item.hotPaths);
        } else {
          item
            ..attempts += 1
            ..lastError = job.error ?? job.status.name;
          if (job.status == TransferStatus.declined || item.attempts >= 10) {
            await outbox.remove(item.id);
          } else {
            await outbox.save();
          }
        }
        notifyListeners();
      }());
    }
  }

  // ─────────────────────────── Hot folders (desktop) ───────────────────────────

  String get hotRoot => p.join(homeDir(), 'SUDOSEND Outbox');
  final Map<String, int> _hotSizes = {};
  final Set<String> _hotQueued = {};

  Future<void> _scanHotFolders() async {
    if (!ready) return;
    final root = Directory(hotRoot);
    try {
      await root.create(recursive: true);
      final readme = File(p.join(root.path, 'README.txt'));
      if (!await readme.exists()) {
        await readme.writeAsString("Drop files or folders into a device's folder here and SUDOSEND sends them "
            'automatically when that device is online. Delivered items move to its "Sent" folder.\n');
      }
      for (final device in trust.all) {
        final dir = Directory(p.join(root.path, sanitizeFileName(device.name)));
        await dir.create(recursive: true);
        await for (final entity in dir.list(followLinks: false)) {
          final name = p.basename(entity.path);
          if (name == 'Sent' || name.startsWith('.') || _hotQueued.contains(entity.path)) continue;
          final size = entity is File ? await entity.length() : await _dirSize(entity as Directory);
          final prev = _hotSizes[entity.path];
          _hotSizes[entity.path] = size;
          if (prev == null || prev != size) continue; // wait until it stops changing
          final files = <FileEntry>[];
          if (entity is File) {
            files.add(FileEntry(name: name, size: size, path: entity.path));
          } else {
            await for (final f in (entity as Directory).list(recursive: true, followLinks: false)) {
              if (f is! File) continue;
              final rel = p.relative(f.path, from: entity.path).split(p.separator).join('/');
              files.add(FileEntry(name: '$name/$rel', size: await f.length(), path: f.path));
            }
          }
          if (files.isEmpty) continue;
          _hotQueued.add(entity.path);
          _hotSizes.remove(entity.path);
          await outbox.add(OutboxItem(
            id: 'hot-${DateTime.now().microsecondsSinceEpoch}',
            fingerprint: device.fingerprint,
            peerName: device.name,
            files: files,
            created: DateTime.now(),
            hotPaths: [entity.path],
          ));
          notifyListeners();
        }
      }
      await _flushOutbox();
    } catch (_) {}
  }

  static Future<int> _dirSize(Directory d) async {
    var total = 0;
    await for (final f in d.list(recursive: true, followLinks: false)) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  Future<void> _archiveHot(List<String> paths) async {
    for (final path in paths) {
      try {
        final sent = Directory(p.join(p.dirname(path), 'Sent'));
        await sent.create(recursive: true);
        var dest = p.join(sent.path, p.basename(path));
        var i = 1;
        while (FileSystemEntity.typeSync(dest) != FileSystemEntityType.notFound) {
          dest = p.join(sent.path, '${p.basenameWithoutExtension(path)} ($i)${p.extension(path)}');
          i++;
        }
        await (FileSystemEntity.isDirectorySync(path) ? Directory(path).rename(dest) : File(path).rename(dest));
      } catch (_) {}
      _hotQueued.remove(path);
    }
  }

  // ─────────────────────────── Previews ───────────────────────────

  Future<Map<int, Uint8List>?> _previewsFor(List<FileEntry> files) async {
    if (!settings.previewsSend || !files.any((f) => isPreviewable(f.name))) return null;
    try {
      return await buildPreviews(files).timeout(const Duration(seconds: 4));
    } catch (_) {
      return null; // never delay a transfer for thumbnails
    }
  }

  // ─────────────────────────── Messages ───────────────────────────

  /// The thread currently on screen (its messages are not counted as unread).
  String? openThread;

  void _watchChatJob(TransferJob job) {
    var finished = false;
    job.changes.listen((_) {
      if (finished || job.isActive) return;
      finished = true;
      if (job.direction == TransferDirection.incoming && job.status == TransferStatus.done) {
        final fp = job.peerFingerprint ?? '';
        final visible = foreground && tab == 3 && openThread == fp;
        chat.add(fp, job.peerName, job.text ?? '', outgoing: false, unread: !visible);
        if (!visible && settings.notifications) {
          final title = t('chat_from', {'name': job.peerName});
          final body = (job.text ?? '').length > 160 ? '${job.text!.substring(0, 160)}…' : (job.text ?? '');
          if (Platform.isAndroid) {
            unawaited(_native.notify(job.id, title, body));
          } else if (!foreground) {
            unawaited(desktopNotify(title, body));
          } else {
            _messages.add('$title: $body');
          }
        }
        notifyListeners();
      }
      job.dispose();
    });
  }

  /// Sends a chat message to a trusted device. Failures are kept and can be retried.
  Future<void> sendChat(String fingerprint, String name, String text, {ChatMessage? retry}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > kMaxTextLength) return;
    final msg = retry ?? chat.add(fingerprint, name, trimmed, outgoing: true);
    msg.state = ChatState.sending;
    notifyListeners();
    final peer = peers.where((p) => p.id == fingerprint).firstOrNull;
    if (peer == null) {
      msg.state = ChatState.failed;
    } else {
      final job = await _engine.send(peer, const [], text: msg.text, chat: true);
      msg.state = job.status == TransferStatus.done ? ChatState.sent : ChatState.failed;
    }
    await chat.save();
    notifyListeners();
  }

  void markThreadRead(String fingerprint) {
    chat.markRead(fingerprint);
    notifyListeners();
  }

  void clearThread(String fingerprint) {
    chat.clear(fingerprint);
    notifyListeners();
  }

  // ─────────────────────────── Speed test ───────────────────────────

  /// Measures encrypted throughput to a trusted device. Returns (bytes/s, error).
  Future<(double?, String?)> speedTest(Peer peer) async {
    try {
      return (await _engine.speedTest(peer), null);
    } on WraithException catch (e) {
      return (null, e.message.contains('declined') ? t('speed_declined') : e.message);
    } catch (e) {
      return (null, describeError(e));
    }
  }

  // ─────────────────────────── Folder sync ───────────────────────────

  Timer? _syncTimer;
  final Set<String> _syncBusy = {};

  /// iOS keeps apps inside their sandbox; picking an arbitrary folder to keep
  /// in sync there is not reliable, so the feature is off on iOS for now.
  bool get syncSupported => !Platform.isIOS && settings.folderSync;

  Directory? _syncFolderFor(String id, String fingerprint) {
    if (!settings.folderSync) return null;
    for (final s in settings.syncPairs) {
      if (s.id == id && s.fingerprint == fingerprint && s.enabled) return Directory(s.path);
    }
    return null;
  }

  SyncPair? _pairById(String id) => settings.syncPairs.where((s) => s.id == id).firstOrNull;

  void _watchSyncJob(TransferJob job) {
    var finished = false;
    job.changes.listen((_) {
      if (finished || job.isActive) return;
      finished = true;
      final pair = _pairById(job.syncId!);
      if (pair != null) {
        if (job.status == TransferStatus.done) {
          pair.lastSync = DateTime.now();
          pair.lastError = null;
          if (job.direction == TransferDirection.outgoing) pair.pushed += job.files.length;
        } else {
          pair.lastError = job.error ?? job.status.name;
        }
        unawaited(settings.update((_) {}));
      }
      job.dispose();
    });
  }

  /// Picks a folder and invites [peer] to keep it in sync. Returns an error or null.
  Future<String?> createSync(Peer peer) async {
    if (!trust.isTrusted(peer.id)) return t('sync_trusted_only');
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return null;
    final dir = Directory(path);
    if (!await _isWritable(dir)) return t('err_not_writable');
    final id = newPairingToken().substring(0, 16);
    final name = p.basename(p.normalize(path));
    // Save first so the partner's first manifest request already finds it.
    final pair = SyncPair(id: id, name: name, path: dir.path, fingerprint: peer.id, peerName: peer.name);
    await settings.update((s) => s.syncPairs = [...s.syncPairs, pair]);
    try {
      final ok = await _engine.sendSyncInvite(peer, id, name);
      if (!ok) {
        await removeSync(id);
        return t('sync_declined', {'name': peer.name});
      }
    } catch (e) {
      await removeSync(id);
      return describeError(e);
    }
    _applySettings();
    unawaited(syncNow());
    return null;
  }

  /// Answers a sync invitation: the user picks the local folder. Returns false if cancelled.
  Future<bool> acceptSyncInvite(IncomingRequest r) async {
    final invite = r.syncInvite!;
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || !r.isPending) return false;
    final dir = Directory(path);
    if (!await _isWritable(dir)) {
      _messages.add(t('err_not_writable'));
      return false;
    }
    final pair = SyncPair(id: invite.id, name: invite.name, path: dir.path, fingerprint: r.fingerprint, peerName: r.peerName);
    await settings.update((s) => s.syncPairs = [...s.syncPairs.where((x) => x.id != invite.id), pair]);
    r.respond(true, trust: true); // syncing implies trusting this device
    _applySettings();
    return true;
  }

  Future<void> removeSync(String id) async {
    await settings.update((s) => s.syncPairs = s.syncPairs.where((x) => x.id != id).toList());
    _applySettings();
    notifyListeners();
  }

  Future<void> setSyncEnabled(String id, bool enabled) async {
    final pair = _pairById(id);
    if (pair == null) return;
    await settings.update((_) => pair.enabled = enabled);
    _applySettings();
    if (enabled) unawaited(syncNow());
  }

  /// One sync round for every enabled pair whose device is online: fetch
  /// the partner's manifest and push what is new or newer here. The partner
  /// does the same in the other direction.
  Future<void> syncNow() async {
    if (!ready || !settings.folderSync) return;
    for (final pair in List.of(settings.syncPairs)) {
      if (!pair.enabled || _syncBusy.contains(pair.id)) continue;
      final peer = peers.where((x) => x.id == pair.fingerprint).firstOrNull;
      if (peer == null || !trust.isTrusted(pair.fingerprint)) continue;
      _syncBusy.add(pair.id);
      try {
        final root = Directory(pair.path);
        final remote = await _engine.fetchManifest(peer, pair.id);
        final local = await buildManifest(root);
        final push = planPush(local, remote);
        if (push.isEmpty) {
          pair.lastSync = DateTime.now();
          pair.lastError = null;
        } else {
          final files = [
            for (final e in push.take(2000))
              FileEntry(name: e.path, size: e.size, path: p.joinAll([root.path, ...e.path.split('/')]), mtime: e.mtime),
          ];
          final job = await _engine.send(peer, files, syncId: pair.id);
          if (job.status != TransferStatus.done) pair.lastError = job.error ?? job.status.name;
        }
      } catch (e) {
        pair.lastError = describeError(e);
      } finally {
        _syncBusy.remove(pair.id);
      }
      await settings.update((_) {});
    }
    notifyListeners();
  }

  bool isSyncing(String id) => _syncBusy.contains(id);

  // ─────────────────────────── Updates ───────────────────────────

  /// Set when a newer release exists (shown as a badge on the settings button).
  UpdateInfo? updateAvailable;

  /// Returns (newer release or null, error or null).
  Future<(UpdateInfo?, String?)> checkForUpdates({bool silent = false}) async {
    try {
      final info = await Updater(kAppVersion).latest();
      final newer = Updater.isNewer(info.version, kAppVersion) ? info : null;
      updateAvailable = newer;
      notifyListeners();
      if (newer != null && silent) _messages.add(t('update_available', {'v': newer.version}));
      return (newer, null);
    } catch (e) {
      return (null, e is HttpException ? e.message : describeError(e));
    }
  }

  /// Downloads and starts installing [info]. Returns a user message for the
  /// result, or null when an installer took over.
  Future<String?> installUpdate(UpdateInfo info, {void Function(double)? onProgress}) async {
    final method = Updater.method;
    if (method == UpdateMethod.openPage || method == UpdateMethod.linuxCommand) {
      await openUrl(info.page);
      return null;
    }
    final asset = Updater.pick(info, androidAbi: Platform.isAndroid ? await _native.abi() : '');
    if (asset == null) {
      await openUrl(info.page);
      return null;
    }
    try {
      final Directory dir;
      if (method == UpdateMethod.downloadAndReveal) {
        dir = Directory(p.join((await getDownloadsDirectory())?.path ?? homeDir(), 'SUDOSEND'));
      } else {
        dir = Directory(p.join((await getTemporaryDirectory()).path, 'sudosend-update'));
      }
      final file = await Updater.download(asset, dir, onProgress: onProgress);
      switch (method) {
        case UpdateMethod.androidApk:
          final r = await _native.installApk(file.path);
          if (r == 'permission') return t('update_allow_install');
          if (r != 'ok') return t('update_failed');
          return null;
        case UpdateMethod.windowsInstaller:
          await Process.start(file.path, const [], mode: ProcessStartMode.detached);
          // The installer replaces the running exe, so step aside.
          Future<void>.delayed(const Duration(seconds: 1), () => exit(0));
          return null;
        default:
          await reveal(file.path);
          return t('update_downloaded', {'path': file.path});
      }
    } catch (e) {
      return e is HttpException ? e.message : describeError(e);
    }
  }

  // ─────────────────────────── Find my device ───────────────────────────

  final DesktopRinger _ringer = DesktopRinger();
  final StreamController<String> _rings = StreamController<String>.broadcast();

  /// Fires with the requesting device's name when this device starts ringing.
  Stream<String> get rings => _rings.stream;

  void _startRinging(String from) {
    if (Platform.isAndroid) {
      unawaited(_native.ring(from, title: t('ring_title'), stop: t('ring_stop')));
    } else {
      _ringer.start();
      if (!foreground) unawaited(desktopNotify(t('ring_title'), from));
    }
    _rings.add(from);
  }

  void stopRinging() {
    _ringer.stop();
    unawaited(_native.stopRing());
  }

  /// Makes a trusted device ring. Returns an error message or null.
  Future<String?> ringDevice(Peer peer) async {
    final job = await _engine.send(peer, const [], ring: true);
    if (job.status == TransferStatus.done) return null;
    return job.status == TransferStatus.declined ? t('ring_declined') : (job.error ?? t('ring_declined'));
  }

  Future<void> setStealth(bool value) async {
    await settings.update((s) => s.stealth = value);
    _discovery.stealth = value;
    notifyListeners();
  }

  Future<void> setBackgroundReceive(bool value) async {
    if (value) await _native.requestPermission('notifications');
    await settings.update((s) => s.backgroundReceive = value);
    _lastService = '';
    _updateService();
  }

  Future<void> setNotifications(bool value) async {
    if (value) await _native.requestPermission('notifications');
    await settings.update((s) => s.notifications = value);
  }

  /// Returns an error message, or null on success.
  Future<String?> chooseSaveDir() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return null;
    final dir = Directory(path);
    if (!await _isWritable(dir)) return t('err_not_writable');
    await settings.update((s) => s.saveDir = dir.path);
    saveDir = dir;
    notifyListeners();
    return null;
  }

  Future<void> resetSaveDir() async {
    await settings.update((s) => s.saveDir = null);
    saveDir = await _resolveSaveDir();
    notifyListeners();
  }

  Future<void> rename(String name) async {
    await identity.rename(name);
    if (_pairing != null) refreshPairing(notify: false);
    notifyListeners();
  }

  Future<void> untrust(String fingerprint) async {
    await trust.remove(fingerprint);
    notifyListeners();
  }

  Future<void> unblock(String fingerprint) async {
    await trust.unblock(fingerprint);
    notifyListeners();
  }

  Future<void> rescan() async {
    if (!ready) return;
    await _discovery.rescan();
    await _refreshAddresses();
    notifyListeners();
  }

  Future<void> _refreshAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final found = [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.isLinkLocal) a,
      ];
      final changed = found.map((a) => a.address).join(',') != localAddresses.map((a) => a.address).join(',');
      localAddresses = found;
      if (changed && _pairing != null) refreshPairing(notify: false);
    } catch (_) {
      localAddresses = const [];
    }
  }

  Future<Directory> _resolveSaveDir() async {
    final custom = settings.saveDir;
    if (custom != null && await _isWritable(Directory(custom))) return Directory(custom);
    Directory? preferred;
    try {
      if (Platform.isAndroid) {
        await _native.requestPermission('storage');
        final downloads = await _native.downloadsDir();
        if (downloads != null) preferred = Directory(p.join(downloads, 'SUDOSEND'));
      } else if (!Platform.isIOS) {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) preferred = Directory(p.join(downloads.path, 'SUDOSEND'));
      }
    } catch (_) {}
    if (preferred != null && await _isWritable(preferred)) return preferred;

    final fallback = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'SUDOSEND'));
    await fallback.create(recursive: true);
    return fallback;
  }

  Future<bool> _isWritable(Directory dir) async {
    try {
      await dir.create(recursive: true);
      final probe = File(p.join(dir.path, '.sudosend-probe'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _outboxTimer?.cancel();
    _syncTimer?.cancel();
    _hotTimer?.cancel();
    _ringer.stop();
    _clipTimer?.cancel();
    unawaited(webShare?.stop());
    if (hotspot != null) unawaited(_native.stopHotspot());
    if (ready) {
      unawaited(_discovery.stop());
      unawaited(_engine.stop());
    }
    _lifecycle?.dispose();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_native.releaseMulticastLock());
    unawaited(_native.service('off'));
    _incoming.close();
    _messages.close();
    super.dispose();
  }
}
