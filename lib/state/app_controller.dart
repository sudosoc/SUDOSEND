import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wraith_core/discovery.dart';
import 'package:wraith_core/identity.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/pairing.dart';
import 'package:wraith_core/transfer.dart';
import 'package:wraith_core/util.dart';
import 'package:wraith_core/vault_windows.dart';
import 'package:wraith_core/wraith.dart';

import '../app/strings.dart';
import '../platform/desktop.dart';
import '../platform/native_bridge.dart';
import 'history.dart';
import 'settings.dart';

class AppController extends ChangeNotifier {
  AppController({this.initialArgs = const []});

  final List<String> initialArgs;
  final SettingsController settings = SettingsController();
  final NativeBridge _native = NativeBridge.instance;

  late DeviceIdentity identity;
  late TrustStore trust;
  late HistoryStore history;
  late Discovery _discovery;
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
      saveDir = await _resolveSaveDir();

      _engine = TransferEngine(
        identity: identity,
        trust: trust,
        saveDir: () async => saveDir!,
        autoAccept: (r) => settings.autoAcceptTrusted && r.trusted,
        onIncoming: _onIncoming,
        onJob: _addJob,
        onRejected: (address, reason) {
          rejectedConnections++;
          notifyListeners();
        },
      );
      await _engine.start();

      _discovery = Discovery(identity: identity, transferPort: _engine.port, onChanged: notifyListeners)
        ..stealth = settings.stealth;
      await _discovery.start();
      await _refreshAddresses();

      _lifecycle = AppLifecycleListener(onStateChange: (state) {
        foreground = state == AppLifecycleState.resumed;
        if (foreground) unawaited(_refreshAddresses().then((_) => notifyListeners()));
      });
      foreground = WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

      _subs.add(_native.shares.listen((_) => _importShare()));
      _subs.add(_native.notificationActions.listen(_onNotificationAction));
      if (isDesktop) unawaited(SingleInstance.listen((args) => addPaths(args)));

      ready = true;
      notifyListeners();

      if (identity.regenerated) _messages.add(t('identity_regenerated'));
      if (Platform.isAndroid) {
        if (settings.notifications) await _native.requestPermission('notifications');
        await _importShare();
        _updateService();
      }
      if (initialArgs.isNotEmpty) await addPaths(initialArgs);
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
    _pendingRequests[r.id] = r;
    tab = 1;
    notifyListeners();
    _incoming.add(r);
    final what = r.text != null
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
    unawaited(history.add(HistoryEntry.fromJob(job)));
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

  String _lastService = '';
  DateTime _lastServiceAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Keeps the Android foreground service in step with transfer activity.
  void _updateService() {
    if (!Platform.isAndroid || !ready) return;
    final active = jobs.where((j) => j.isActive).toList();
    String mode;
    String text;
    var progress = -1;
    if (active.isNotEmpty) {
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
    await _engine.send(peer, files, text: text, pairToken: pairToken);
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
