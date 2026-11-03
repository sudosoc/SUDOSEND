import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:wraith_core/identity.dart';

class SharedPayload {
  const SharedPayload(this.files, this.text);
  final List<({String path, String name, int size})> files;
  final String? text;
}

/// An app installed on this Android device (for app sharing).
class InstalledApp {
  const InstalledApp({
    required this.label,
    required this.package,
    required this.version,
    required this.paths,
    required this.size,
    required this.system,
    required this.updated,
    this.icon,
  });

  final String label;
  final String package;
  final String version;

  /// base.apk first, then split APKs (if any).
  final List<String> paths;
  final int size;
  final bool system;
  final DateTime updated;
  final Uint8List? icon;

  bool get isSplit => paths.length > 1;
}

/// A phone seen over Wi-Fi Direct.
class P2pPeer {
  const P2pPeer({required this.name, required this.address, required this.status, this.sudosendName});
  final String name;
  final String address; // Wi-Fi Direct MAC, used to connect
  /// 0 connected, 1 invited, 2 failed, 3 available, 4 unavailable.
  final int status;

  /// Set when the phone advertises SUDOSEND (its SUDOSEND device name).
  final String? sudosendName;

  bool get runsSudosend => sudosendName != null;
  String get label => sudosendName ?? name;
}

/// The current Wi-Fi Direct link.
class P2pLink {
  const P2pLink({required this.owner, this.ownerAddress, this.peerName});
  final bool owner;
  final String? ownerAddress; // always 192.168.49.1 in practice
  final String? peerName;
}

sealed class P2pEvent {
  const P2pEvent();
}

class P2pState extends P2pEvent {
  const P2pState(this.enabled);
  final bool enabled;
}

class P2pPeers extends P2pEvent {
  const P2pPeers(this.peers);
  final List<P2pPeer> peers;
}

class P2pConnection extends P2pEvent {
  const P2pConnection(this.link);

  /// null = not connected.
  final P2pLink? link;
}

class P2pError extends P2pEvent {
  const P2pError(this.reason);
  final String reason; // permission | busy | unsupported | error
}

class NotificationAction {
  const NotificationAction(this.id, this.action);
  final String id;

  /// accept | decline | open
  final String action;
}

/// Dart side of the Android `sudosend/native` channel. Every call is a no-op
/// (or returns a neutral value) on other platforms and when the native side
/// is unavailable, so callers never need to guard.
class NativeBridge {
  NativeBridge._() {
    if (Platform.isAndroid) _channel.setMethodCallHandler(_onCall);
  }

  static final NativeBridge instance = NativeBridge._();
  static const MethodChannel _channel = MethodChannel('sudosend/native');

  final StreamController<void> _shares = StreamController<void>.broadcast();
  final StreamController<NotificationAction> _actions = StreamController<NotificationAction>.broadcast();
  final StreamController<void> _hotspotStopped = StreamController<void>.broadcast();
  final StreamController<void> _ringStopped = StreamController<void>.broadcast();
  final StreamController<P2pEvent> _p2p = StreamController<P2pEvent>.broadcast();
  final StreamController<Map<String, Object?>> _installs = StreamController<Map<String, Object?>>.broadcast();

  /// Results of app installs: {ok, status, message, package}.
  Stream<Map<String, Object?>> get installResults => _installs.stream;

  Stream<P2pEvent> get p2pEvents => _p2p.stream;

  Stream<void> get ringStopped => _ringStopped.stream;

  Stream<void> get hotspotStopped => _hotspotStopped.stream;

  /// Fires when another app shared files/text to SUDOSEND; fetch with [takeShare].
  Stream<void> get shares => _shares.stream;
  Stream<NotificationAction> get notificationActions => _actions.stream;

  bool get available => Platform.isAndroid;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onShare':
        _shares.add(null);
      case 'onRingStopped':
        _ringStopped.add(null);
      case 'onHotspotStopped':
        _hotspotStopped.add(null);
      case 'onInstallResult':
        _installs.add(Map<String, Object?>.from(call.arguments as Map));
      case 'onP2p':
        final e = _parseP2p(Map<Object?, Object?>.from(call.arguments as Map));
        if (e != null) _p2p.add(e);
      case 'onNotificationAction':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        _actions.add(NotificationAction(m['id'] as String, m['action'] as String));
    }
    return null;
  }

  static P2pEvent? _parseP2p(Map<Object?, Object?> m) {
    switch (m['type']) {
      case 'state':
        return P2pState(m['enabled'] == true);
      case 'error':
        return P2pError('${m['reason']}');
      case 'connection':
        if (m['connected'] != true) return const P2pConnection(null);
        return P2pConnection(P2pLink(
          owner: m['owner'] == true,
          ownerAddress: m['ownerAddress'] as String?,
          peerName: m['peerName'] as String?,
        ));
      case 'peers':
        final list = <P2pPeer>[];
        for (final raw in (m['peers'] as List<Object?>? ?? const [])) {
          final p = Map<Object?, Object?>.from(raw as Map);
          list.add(P2pPeer(
            name: (p['name'] as String?) ?? '',
            address: (p['address'] as String?) ?? '',
            status: (p['status'] as num?)?.toInt() ?? 4,
            sudosendName: p['sudosend'] as String?,
          ));
        }
        return P2pPeers(list);
    }
    return null;
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    if (!available) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  Future<void> acquireMulticastLock() => _invoke<bool>('acquireMulticastLock');
  Future<void> releaseMulticastLock() => _invoke<bool>('releaseMulticastLock');
  Future<String?> downloadsDir() => _invoke<String>('downloadsDir');

  /// mode: off | idle | active. [progress] 0–100, or -1 for none.
  Future<void> service(String mode, {String title = 'SUDOSEND', String text = '', int progress = -1}) =>
      _invoke<bool>('service', {'mode': mode, 'title': title, 'text': text, 'progress': progress});

  Future<void> notifyIncoming(String id, String title, String text, {required String accept, required String decline}) =>
      _invoke<bool>('notifyIncoming', {'id': id, 'title': title, 'text': text, 'accept': accept, 'decline': decline});

  Future<void> notify(String id, String title, String text) =>
      _invoke<bool>('notify', {'id': id, 'title': title, 'text': text});

  Future<void> cancelNotification(String id) => _invoke<bool>('cancelNotification', {'id': id});

  Future<bool> requestPermission(String name) async =>
      (await _invoke<bool>('requestPermission', {'name': name})) ?? true;

  Future<bool> openFile(String path) async => (await _invoke<bool>('openFile', {'path': path})) ?? false;
  Future<bool> openUrl(String url) async => (await _invoke<bool>('openUrl', {'url': url})) ?? false;

  Future<bool> isLowRam() async => (await _invoke<bool>('isLowRam')) ?? false;

  /// Primary CPU ABI, e.g. "arm64-v8a".
  Future<String> abi() async => (await _invoke<String>('abi')) ?? '';

  /// "ok" | "permission" | "error" — see Bridge.installApk.
  Future<String> installApk(String path) async => (await _invoke<String>('installApk', {'path': path})) ?? 'error';

  /// Apps in the launcher, with their APK files.
  Future<List<InstalledApp>> listApps() async {
    final raw = await _invoke<List<Object?>>('listApps');
    return [
      for (final r in raw ?? const <Object?>[])
        if (r is Map)
          InstalledApp(
            label: r['label'] as String? ?? '?',
            package: r['package'] as String? ?? '',
            version: r['version'] as String? ?? '',
            paths: [for (final x in (r['paths'] as List<Object?>? ?? const [])) '$x'],
            size: (r['size'] as num?)?.toInt() ?? 0,
            system: r['system'] == true,
            updated: DateTime.fromMillisecondsSinceEpoch((r['updated'] as num?)?.toInt() ?? 0),
            icon: r['icon'] as Uint8List?,
          ),
    ];
  }

  /// Name, package, version, permissions, signer of an APK file (null if not an APK).
  Future<Map<String, Object?>?> apkInfo(String path) async {
    final r = await _invoke<Map<Object?, Object?>>('apkInfo', {'path': path});
    return r == null ? null : {for (final e in r.entries) '${e.key}': e.value};
  }

  /// "ok" (Android shows its confirm screen) | "permission" | "error: …".
  Future<String> installApks(List<String> paths) async =>
      (await _invoke<String>('installApks', {'paths': paths})) ?? 'error';

  /// (free, total) bytes of the volume holding [path].
  Future<(int, int)?> diskSpace(String path) async {
    final r = await _invoke<List<Object?>>('diskSpace', {'path': path});
    if (r == null || r.length < 2) return null;
    return ((r[0] as num).toInt(), (r[1] as num).toInt());
  }

  /// Starts a local-only hotspot. Returns (ssid, password); throws a
  /// user-readable message on failure.
  Future<({String ssid, String password})> startHotspot() async {
    if (!available) throw 'Hotspot mode is available on Android';
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('startHotspot');
      final ssid = m?['ssid'] as String?;
      if (ssid == null) throw 'Hotspot did not report its name';
      return (ssid: ssid, password: (m?['password'] as String?) ?? '');
    } on PlatformException catch (e) {
      throw e.message ?? e.code;
    }
  }

  Future<void> stopHotspot() => _invoke<bool>('stopHotspot');

  /// Listens for Wi-Fi Direct changes and advertises this phone as SUDOSEND.
  Future<bool> p2pAttach(String name, String fingerprint) async =>
      (await _invoke<bool>('p2pAttach', {'name': name, 'fp': fingerprint})) ?? false;
  Future<void> p2pScan() => _invoke<bool>('p2pScan');
  Future<void> p2pStopScan() => _invoke<bool>('p2pStopScan');
  Future<void> p2pDisconnect() => _invoke<bool>('p2pDisconnect');

  /// Sends a Wi-Fi Direct invitation. Returns null on success or a reason.
  Future<String?> p2pConnect(String address) async {
    if (!available) return 'unsupported';
    try {
      await _channel.invokeMethod<bool>('p2pConnect', {'address': address});
      return null;
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  Future<void> ring(String name, {required String title, required String stop}) =>
      _invoke<bool>('ring', {'name': name, 'title': title, 'stop': stop});
  Future<void> stopRing() => _invoke<bool>('stopRing');

  Future<SharedPayload?> takeShare() async {
    final raw = await _invoke<Map<Object?, Object?>>('takeShare');
    if (raw == null) return null;
    final files = <({String path, String name, int size})>[];
    for (final f in (raw['files'] as List<Object?>? ?? const [])) {
      final m = Map<String, Object?>.from(f as Map);
      files.add((path: m['path'] as String, name: m['name'] as String, size: (m['size'] as num).toInt()));
    }
    final text = raw['text'] as String?;
    if (files.isEmpty && (text == null || text.isEmpty)) return null;
    return SharedPayload(files, text);
  }
}

/// Seals the identity seed with a non-exportable Android Keystore key.
class AndroidKeystoreVault implements SeedVault {
  static const MethodChannel _channel = MethodChannel('sudosend/native');

  @override
  String get id => 'android-keystore';

  @override
  Future<List<int>> seal(List<int> secret) async {
    final out = await _channel.invokeMethod<Uint8List>('vaultSeal', {'data': Uint8List.fromList(secret)});
    if (out == null) throw StateError('Keystore unavailable');
    return out;
  }

  @override
  Future<List<int>> open(List<int> sealed) async {
    final out = await _channel.invokeMethod<Uint8List>('vaultOpen', {'data': Uint8List.fromList(sealed)});
    if (out == null) throw StateError('Keystore unavailable');
    return out;
  }
}
