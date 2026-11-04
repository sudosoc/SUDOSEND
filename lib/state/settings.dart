import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'safe_file.dart';

/// What one trusted device is allowed to do here. Global feature switches
/// still apply on top: a feature that is off is off for every device.
class DevicePrefs {
  DevicePrefs({
    this.folder,
    this.autoAccept,
    this.clipboard = true,
    this.ring = true,
    this.chat = true,
    this.sync = true,
    this.speedTest = true,
    this.keepMetadata = false,
    this.nickname,
    this.group,
    this.direction = 'both',
    this.trustExpires,
    this.byType,
    this.byDate,
    this.search = true,
  });

  /// Folder name for this device's files (null = its device name).
  String? folder;

  /// Accept files without asking (null = follow the global setting).
  bool? autoAccept;
  bool clipboard;
  bool ring;
  bool chat;
  bool sync;
  bool speedTest;

  /// Send photos to this device with their metadata (e.g. your own backup).
  bool keepMetadata;

  /// Name shown for this device inside SUDOSEND (its own name stays as is).
  String? nickname;

  /// Device group, e.g. Personal or Work.
  String? group;

  /// both | receiveOnly (it may send to me, I never send to it) |
  /// sendOnly (I may send to it, it may not send to me).
  String direction;

  /// When trust in this device ends by itself (null = never).
  DateTime? trustExpires;

  /// Archiving rules for this device (null = follow the general setting).
  bool? byType;
  bool? byDate;

  /// May search this device's received files and ask for a copy.
  bool search;

  bool get mayReceiveFrom => direction != 'sendOnly';
  bool get maySendTo => direction != 'receiveOnly';

  Map<String, Object?> toJson() => {
        if (folder != null) 'folder': folder,
        if (autoAccept != null) 'autoAccept': autoAccept,
        'clipboard': clipboard,
        'ring': ring,
        'chat': chat,
        'sync': sync,
        'speedTest': speedTest,
        'keepMetadata': keepMetadata,
        if (nickname != null) 'nickname': nickname,
        if (group != null) 'group': group,
        if (direction != 'both') 'direction': direction,
        if (trustExpires != null) 'trustExpires': trustExpires!.millisecondsSinceEpoch,
        if (byType != null) 'byType': byType,
        if (byDate != null) 'byDate': byDate,
        'search': search,
      };

  static DevicePrefs fromJson(Object? raw) {
    if (raw is! Map) return DevicePrefs();
    bool b(String k, bool d) => raw[k] is bool ? raw[k] as bool : d;
    final folder = raw['folder'];
    return DevicePrefs(
      folder: folder is String && folder.trim().isNotEmpty ? folder : null,
      autoAccept: raw['autoAccept'] is bool ? raw['autoAccept'] as bool : null,
      clipboard: b('clipboard', true),
      ring: b('ring', true),
      chat: b('chat', true),
      sync: b('sync', true),
      speedTest: b('speedTest', true),
      keepMetadata: b('keepMetadata', false),
      nickname: raw['nickname'] is String && (raw['nickname'] as String).trim().isNotEmpty ? raw['nickname'] as String : null,
      group: raw['group'] is String ? raw['group'] as String : null,
      direction: const {'both', 'receiveOnly', 'sendOnly'}.contains(raw['direction']) ? raw['direction'] as String : 'both',
      trustExpires:
          raw['trustExpires'] is int ? DateTime.fromMillisecondsSinceEpoch(raw['trustExpires'] as int) : null,
      byType: raw['byType'] is bool ? raw['byType'] as bool : null,
      byDate: raw['byDate'] is bool ? raw['byDate'] as bool : null,
      search: b('search', true),
    );
  }
}

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

  /// Desktop: send whatever is dropped into "SUDOSEND Outbox/&lt;device&gt;/".
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

  /// Smart organization of received files: device / type / date folders.
  bool organize = true;
  bool organizeByDevice = true;
  bool organizeByType = true;
  bool organizeByDate = true;

  /// Photo metadata before sending: off | location | all.
  String metadata = 'location';

  /// A received file identical to one you already have: keep | remove.
  String duplicates = 'keep';

  /// Decline transfers that would not fit on this device.
  bool storageGuard = true;

  /// Notification types.
  bool notifyDone = true;
  bool notifyFailed = true;
  bool notifyDuplicates = true;
  bool notifyStorage = true;

  /// Android: share installed apps; include system apps in the list.
  bool shareApps = true;
  bool showSystemApps = false;

  /// File Metadata Explorer in previews, and whether GPS positions are shown.
  bool showMetadata = true;
  bool showGps = true;

  /// Deleted files go to a trash for this many days (0 = delete at once).
  int trashDays = 30;

  /// Trusted devices may search the files received here and ask for a copy.
  bool remoteSearch = true;
  int remoteSearchLimit = 50;

  /// Device groups (names), e.g. Personal, Work.
  List<String> deviceGroups = ['Personal', 'Work'];

  /// Per-device permissions, keyed by fingerprint.
  Map<String, DevicePrefs> devicePrefs = {};

  DevicePrefs prefsFor(String fingerprint) => devicePrefs[fingerprint] ?? DevicePrefs();
  /// Android: phone-to-phone Wi-Fi Direct links.
  bool wifiDirect = true;
  /// Look for a new version on GitHub once at startup.
  bool autoUpdateCheck = true;
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
      final m = await SafeFile.readJson(_file!, (j) => j as Map<String, dynamic>);
      if (m != null) {
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
        organize = (m['organize'] as bool?) ?? organize;
        organizeByDevice = (m['organizeByDevice'] as bool?) ?? organizeByDevice;
        organizeByType = (m['organizeByType'] as bool?) ?? organizeByType;
        organizeByDate = (m['organizeByDate'] as bool?) ?? organizeByDate;
        final dup = m['duplicates'];
        if (dup == 'keep' || dup == 'remove') duplicates = dup as String;
        storageGuard = (m['storageGuard'] as bool?) ?? storageGuard;
        notifyDone = (m['notifyDone'] as bool?) ?? notifyDone;
        notifyFailed = (m['notifyFailed'] as bool?) ?? notifyFailed;
        notifyDuplicates = (m['notifyDuplicates'] as bool?) ?? notifyDuplicates;
        notifyStorage = (m['notifyStorage'] as bool?) ?? notifyStorage;
        shareApps = (m['shareApps'] as bool?) ?? shareApps;
        showSystemApps = (m['showSystemApps'] as bool?) ?? showSystemApps;
        showMetadata = (m['showMetadata'] as bool?) ?? showMetadata;
        showGps = (m['showGps'] as bool?) ?? showGps;
        trashDays = (m['trashDays'] as int?) ?? trashDays;
        remoteSearch = (m['remoteSearch'] as bool?) ?? remoteSearch;
        remoteSearchLimit = ((m['remoteSearchLimit'] as int?) ?? remoteSearchLimit).clamp(10, 200);
        final groups = m['deviceGroups'];
        if (groups is List) deviceGroups = groups.whereType<String>().toList();
        final md = m['metadata'];
        if (md == 'off' || md == 'location' || md == 'all') metadata = md as String;
        final prefs = m['devicePrefs'];
        if (prefs is Map) {
          devicePrefs = {for (final e in prefs.entries) '${e.key}': DevicePrefs.fromJson(e.value)};
        }
        wifiDirect = (m['wifiDirect'] as bool?) ?? wifiDirect;
        autoUpdateCheck = (m['autoUpdateCheck'] as bool?) ?? autoUpdateCheck;
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
      await SafeFile.write(file, jsonEncode({
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
        'organize': organize,
        'organizeByDevice': organizeByDevice,
        'organizeByType': organizeByType,
        'organizeByDate': organizeByDate,
        'metadata': metadata,
        'duplicates': duplicates,
        'storageGuard': storageGuard,
        'notifyDone': notifyDone,
        'notifyFailed': notifyFailed,
        'notifyDuplicates': notifyDuplicates,
        'notifyStorage': notifyStorage,
        'deviceGroups': deviceGroups,
        'shareApps': shareApps,
        'showSystemApps': showSystemApps,
        'showMetadata': showMetadata,
        'showGps': showGps,
        'trashDays': trashDays,
        'remoteSearch': remoteSearch,
        'remoteSearchLimit': remoteSearchLimit,
        'devicePrefs': {for (final e in devicePrefs.entries) e.key: e.value.toJson()},
        'wifiDirect': wifiDirect,
        'autoUpdateCheck': autoUpdateCheck,
        'syncPairs': [for (final s in syncPairs) s.toJson()],
      }));
    } catch (_) {}
  }
}
