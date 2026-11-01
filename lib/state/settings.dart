import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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
      }));
    } catch (_) {}
  }
}
