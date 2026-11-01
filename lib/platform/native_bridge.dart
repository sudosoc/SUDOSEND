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
      case 'onNotificationAction':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        _actions.add(NotificationAction(m['id'] as String, m['action'] as String));
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
