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
  bool reduceEffects = Abi.current() == Abi.linuxArm64; // Raspberry Pi & co.
  bool autoAcceptTrusted = false;
  bool stealth = false;
  bool backgroundReceive = false;
  bool notifications = true;
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
        reduceEffects = (m['reduceEffects'] as bool?) ?? reduceEffects;
        autoAcceptTrusted = (m['autoAcceptTrusted'] as bool?) ?? autoAcceptTrusted;
        stealth = (m['stealth'] as bool?) ?? stealth;
        backgroundReceive = (m['backgroundReceive'] as bool?) ?? backgroundReceive;
        notifications = (m['notifications'] as bool?) ?? notifications;
        saveDir = m['saveDir'] as String?;
      }
    } catch (_) {
      // Corrupt settings: keep defaults.
    }
    notifyListeners();
  }

  Future<void> update(void Function(SettingsController s) change) async {
    change(this);
    notifyListeners();
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'language': language,
        'reduceEffects': reduceEffects,
        'autoAcceptTrusted': autoAcceptTrusted,
        'stealth': stealth,
        'backgroundReceive': backgroundReceive,
        'notifications': notifications,
        'saveDir': saveDir,
      }));
    } catch (_) {}
  }
}
