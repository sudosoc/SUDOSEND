import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// One folder kept in sync with one trusted device.
class SyncPair {
  SyncPair({
    required this.id,
    required this.name,
    required this.path,
    required this.fingerprint,
    required this.peerName,
    this.enabled = true,
    this.lastSync,
    this.lastError,
    this.pushed = 0,
  });

  final String id;
  final String name;
  final String path;
  final String fingerprint;
  String peerName;
  bool enabled;
  DateTime? lastSync;
  String? lastError;
  int pushed; // files sent by this side, lifetime

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'fp': fingerprint,
        'peer': peerName,
        'enabled': enabled,
        if (lastSync != null) 'last': lastSync!.millisecondsSinceEpoch,
        'pushed': pushed,
      };

  static SyncPair? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return SyncPair(
        id: raw['id'] as String,
        name: raw['name'] as String,
        path: raw['path'] as String,
        fingerprint: raw['fp'] as String,
        peerName: raw['peer'] as String? ?? '?',
        enabled: raw['enabled'] as bool? ?? true,
        lastSync: raw['last'] is int ? DateTime.fromMillisecondsSinceEpoch(raw['last'] as int) : null,
        pushed: raw['pushed'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// User preferences, stored as settings.json next to the identity.
class SettingsController extends ChangeNotifier {
  File? _file;

  String language = 'system'; // system | en | ar
  /// Visual effects: full (live blur + animated backdrop), balanced (glass
  /// look without live blur — default), lite (no shadows/animations).
  String effects = Abi.current() == Abi.linuxArm64 ? 'lite' : 'balanced';
  bool _effectsSaved = false;
  bool get effectsChosen => _effectsSaved;
  bool get reduceEffects => effects == 'lite';
  bool clipboardSync = false;

  /// Upload cap in MB/s (0 = unlimited).
  int uploadLimit = 0;

  /// Desktop: send whatever is dropped into "SUDOSEND Outbox/<device>/".
  bool hotFolders = false;

  /// Let trusted devices make this one ring ("find my device").
  bool allowRing = true;
  bool autoAcceptTrusted = false;
  bool stealth = false;
  bool backgroundReceive = false;
  bool notifications = true;
  bool autoCopyText = false;
  bool senderFolders = false;
  String? saveDir;

  // Optional features — every one can be switched off.
  /// Deflate compressible files on the wire (text, logs, code, raw images).
  bool compression = true;
  /// Attach small image thumbnails to outgoing offers.
  bool previewsSend = true;
  /// Show thumbnails that other devices attach to their offers.
  bool previewsShow = true;
  /// Messages tab: short texts between trusted devices, kept as threads.
  bool chat = true;
  /// Two-way folder sync with trusted devices.
  bool folderSync = true;
  /// Let trusted devices run a speed test against this one.
  bool allowSpeedTest = true;
  /// Browser share (send to / receive from devices without the app).
  bool webShare = true;
  /// Queue sends for trusted devices that are offline.
  bool offlineQueue = true;
  /// Sync folders.
  List<SyncPair> syncPairs = [];

  /// Effective UI language.
  String get lang {
    if (language == 'ar' || language == 'en') return language;
    return PlatformDispatcher.instance.locale.languageCode == 'ar' ? 'ar' : 'en';
  }

  bool get rtl => lang == 'ar';

  Future<void> load(Directory dir) async {
    _file = File(p.join(dir.path, 'settings.json'));
    try {
      if (await _file!.exists()) {
        final m = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        language = (m['language'] as String?) ?? language;
        final savedEffects = m['effects'] as String?;
        if (savedEffects == 'full' || savedEffects == 'balanced' || savedEffects == 'lite') {
          effects = savedEffects!;
          _effectsSaved = true;
        } else if (m['reduceEffects'] == true) {
          effects = 'lite';
          _effectsSaved = true;
        }
        clipboardSync = (m['clipboardSync'] as bool?) ?? clipboardSync;
        uploadLimit = (m['uploadLimit'] as int?) ?? uploadLimit;
        hotFolders = (m['hotFolders'] as bool?) ?? hotFolders;
        allowRing = (m['allowRing'] as bool?) ?? allowRing;
        autoAcceptTrusted = (m['autoAcceptTrusted'] as bool?) ?? autoAcceptTrusted;
        stealth = (m['stealth'] as bool?) ?? stealth;
        backgroundReceive = (m['backgroundReceive'] as bool?) ?? backgroundReceive;
        notifications = (m['notifications'] as bool?) ?? notifications;
        autoCopyText = (m['autoCopyText'] as bool?) ?? autoCopyText;
        senderFolders = (m['senderFolders'] as bool?) ?? senderFolders;
        saveDir = m['saveDir'] as String?;
        compression = (m['compression'] as bool?) ?? compression;
        previewsSend = (m['previewsSend'] as bool?) ?? previewsSend;
        previewsShow = (m['previewsShow'] as bool?) ?? previewsShow;
        chat = (m['chat'] as bool?) ?? chat;
        folderSync = (m['folderSync'] as bool?) ?? folderSync;
        allowSpeedTest = (m['allowSpeedTest'] as bool?) ?? allowSpeedTest;
        webShare = (m['webShare'] as bool?) ?? webShare;
        offlineQueue = (m['offlineQueue'] as bool?) ?? offlineQueue;
        final pairs = m['syncPairs'];
        if (pairs is List) syncPairs = pairs.map(SyncPair.fromJson).whereType<SyncPair>().toList();
      }
    } catch (_) {
      // Corrupt settings: keep defaults.
    }
    notifyListeners();
  }

  Future<void> update(void Function(SettingsController s) change) async {
    final before = effects;
    change(this);
    if (effects != before) _effectsSaved = true;
    notifyListeners();
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'language': language,
        'effects': effects,
        'clipboardSync': clipboardSync,
        'uploadLimit': uploadLimit,
        'hotFolders': hotFolders,
        'allowRing': allowRing,
        'autoAcceptTrusted': autoAcceptTrusted,
        'stealth': stealth,
        'backgroundReceive': backgroundReceive,
        'notifications': notifications,
        'autoCopyText': autoCopyText,
        'senderFolders': senderFolders,
        'saveDir': saveDir,
        'compression': compression,
        'previewsSend': previewsSend,
        'previewsShow': previewsShow,
        'chat': chat,
        'folderSync': folderSync,
        'allowSpeedTest': allowSpeedTest,
        'webShare': webShare,
        'offlineQueue': offlineQueue,
        'syncPairs': [for (final s in syncPairs) s.toJson()],
      }));
    } catch (_) {}
  }
}
