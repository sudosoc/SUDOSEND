import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/discovery.dart';
import '../core/identity.dart';
import '../core/models.dart';
import '../core/transfer.dart';
import '../core/wraith.dart';

class AppController extends ChangeNotifier {
  static const MethodChannel _net = MethodChannel('sudosend/net');

  late DeviceIdentity identity;
  late TrustStore trust;
  late Discovery _discovery;
  late TransferEngine _engine;

  bool ready = false;
  String? startupError;
  List<String> localAddresses = const [];
  Directory? saveDir;
  int tab = 0;

  final List<TransferJob> jobs = [];
  final List<FileEntry> selected = [];
  final StreamController<IncomingRequest> _incoming = StreamController<IncomingRequest>.broadcast();

  Stream<IncomingRequest> get incoming => _incoming.stream;
  List<Peer> get peers => ready ? _discovery.peers : const [];
  int get port => ready ? _engine.port : kTransferPort;
  int get selectedBytes => selected.fold<int>(0, (a, f) => a + f.size);
  int get activeJobs => jobs.where((j) => j.isActive).length;

  Future<void> init() async {
    try {
      if (Platform.isAndroid) {
        try {
          await _net.invokeMethod<bool>('acquireMulticastLock');
        } catch (_) {}
      }
      final support = await getApplicationSupportDirectory();
      identity = await DeviceIdentity.loadOrCreate(support);
      trust = await TrustStore.load(support);
      saveDir = await _resolveSaveDir();

      _engine = TransferEngine(
        identity: identity,
        trust: trust,
        saveDir: () async => saveDir!,
        onIncoming: (r) {
          tab = 1;
          notifyListeners();
          _incoming.add(r);
        },
        onJob: _addJob,
      );
      await _engine.start();

      _discovery = Discovery(identity: identity, transferPort: _engine.port, onChanged: notifyListeners);
      await _discovery.start();
      await _refreshAddresses();
      ready = true;
    } catch (e) {
      startupError = describeError(e);
    }
    notifyListeners();
  }

  void setTab(int i) {
    if (tab == i) return;
    tab = i;
    notifyListeners();
  }

  void _addJob(TransferJob job) {
    jobs.insert(0, job);
    job.addListener(_onJobChanged);
    notifyListeners();
  }

  void _onJobChanged() {
    // Only the nav badge depends on job state at this level.
    final active = activeJobs;
    if (active != _lastActive) {
      _lastActive = active;
      notifyListeners();
    }
  }

  int _lastActive = 0;

  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (result == null) return;
    for (final f in result.files) {
      final path = f.path;
      if (path == null || selected.any((s) => s.path == path)) continue;
      selected.add(FileEntry(name: f.name, size: await File(path).length(), path: path));
    }
    notifyListeners();
  }

  void removeSelected(FileEntry f) {
    selected.remove(f);
    notifyListeners();
  }

  void clearSelected() {
    selected.clear();
    notifyListeners();
  }

  Future<void> sendTo(Peer peer) async {
    if (selected.isEmpty) return;
    final files = List<FileEntry>.of(selected);
    selected.clear();
    tab = 2;
    notifyListeners();
    await _engine.send(peer, files);
  }

  /// Accepts "192.168.1.20" or "192.168.1.20:47824".
  Future<String?> sendToAddress(String input) async {
    final text = input.trim();
    final idx = text.lastIndexOf(':');
    final host = idx > 0 ? text.substring(0, idx) : text;
    final port = idx > 0 ? int.tryParse(text.substring(idx + 1)) : kTransferPort;
    final address = InternetAddress.tryParse(host);
    if (address == null || address.type != InternetAddressType.IPv4) return 'Enter a valid IPv4 address';
    if (port == null || port < 1 || port > 65535) return 'Invalid port';
    if (selected.isEmpty) return 'Pick files first';
    unawaited(sendTo(Peer.manual(address, port)));
    return null;
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
      localAddresses = [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (!a.isLoopback) a.address,
      ];
    } catch (_) {
      localAddresses = const [];
    }
  }

  Future<void> rename(String name) async {
    await identity.rename(name);
    notifyListeners();
  }

  Future<void> untrust(String fingerprint) async {
    await trust.remove(fingerprint);
    notifyListeners();
  }

  void clearFinished() {
    jobs.removeWhere((j) {
      final finished = !j.isActive;
      if (finished) j.removeListener(_onJobChanged);
      return finished;
    });
    notifyListeners();
  }

  Future<Directory> _resolveSaveDir() async {
    Directory? preferred;
    try {
      if (Platform.isAndroid) {
        final downloads = await _net.invokeMethod<String>('downloadsDir');
        if (downloads != null) preferred = Directory(p.join(downloads, 'SUDOSEND'));
      } else {
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
    if (Platform.isAndroid) {
      _net.invokeMethod<bool>('releaseMulticastLock').catchError((_) => false);
    }
    _incoming.close();
    super.dispose();
  }
}
