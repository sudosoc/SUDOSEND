import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One period during which a device was visible on the network.
class DeviceSession {
  DeviceSession(this.start, this.end, this.address);
  final DateTime start;
  DateTime end;
  final String address;

  Duration get length => end.difference(start);

  Map<String, Object> toJson() => {'s': start.millisecondsSinceEpoch, 'e': end.millisecondsSinceEpoch, 'a': address};

  static DeviceSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return DeviceSession(
        DateTime.fromMillisecondsSinceEpoch((raw['s'] as num).toInt()),
        DateTime.fromMillisecondsSinceEpoch((raw['e'] as num).toInt()),
        raw['a'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Everything SUDOSEND has learned about a device it has seen.
class DeviceProfile {
  DeviceProfile({
    required this.fingerprint,
    required this.name,
    required this.platform,
    required this.firstSeen,
    required this.lastSeen,
    this.lastAddress,
    this.lastPort,
  });

  final String fingerprint;

  /// Name the device announces (its own setting).
  String name;
  String platform;
  final DateTime firstSeen;
  DateTime lastSeen;
  String? lastAddress;
  int? lastPort;
  final List<DeviceSession> sessions = [];

  Map<String, Object?> toJson() => {
        'name': name,
        'platform': platform,
        'first': firstSeen.millisecondsSinceEpoch,
        'last': lastSeen.millisecondsSinceEpoch,
        if (lastAddress != null) 'addr': lastAddress,
        if (lastPort != null) 'port': lastPort,
        'sessions': [for (final s in sessions) s.toJson()],
      };

  static DeviceProfile? fromJson(String fp, Object? raw) {
    if (raw is! Map) return null;
    try {
      final d = DeviceProfile(
        fingerprint: fp,
        name: raw['name'] as String? ?? '?',
        platform: raw['platform'] as String? ?? 'unknown',
        firstSeen: DateTime.fromMillisecondsSinceEpoch((raw['first'] as num).toInt()),
        lastSeen: DateTime.fromMillisecondsSinceEpoch((raw['last'] as num).toInt()),
        lastAddress: raw['addr'] as String?,
        lastPort: (raw['port'] as num?)?.toInt(),
      );
      d.sessions.addAll((raw['sessions'] as List<dynamic>? ?? const []).map(DeviceSession.fromJson).whereType<DeviceSession>());
      return d;
    } catch (_) {
      return null;
    }
  }
}

/// Device profiles and connection history (devices.json in app data).
class DeviceRegistry {
  DeviceRegistry._(this._file);
  final File _file;
  final Map<String, DeviceProfile> profiles = {};
  static const int maxSessions = 200;

  /// Gaps shorter than this merge into one session (discovery blips).
  static const Duration mergeGap = Duration(minutes: 2);

  static Future<DeviceRegistry> load(Directory dir) async {
    final r = DeviceRegistry._(File(p.join(dir.path, 'devices.json')));
    try {
      if (await r._file.exists()) {
        final m = jsonDecode(await r._file.readAsString()) as Map<String, dynamic>;
        for (final e in m.entries) {
          final d = DeviceProfile.fromJson(e.key, e.value);
          if (d != null) r.profiles[e.key] = d;
        }
      }
    } catch (_) {}
    return r;
  }

  DeviceProfile? operator [](String fp) => profiles[fp];

  /// Records that [fp] is visible right now. Returns true if it just came online.
  bool seen(String fp, {required String name, required String platform, String? address, int? port}) {
    final now = DateTime.now();
    final d = profiles.putIfAbsent(
      fp,
      () => DeviceProfile(fingerprint: fp, name: name, platform: platform, firstSeen: now, lastSeen: now),
    );
    d
      ..name = name
      ..platform = platform == 'unknown' ? d.platform : platform
      ..lastAddress = address ?? d.lastAddress
      ..lastPort = port ?? d.lastPort;
    final last = d.sessions.lastOrNull;
    var fresh = false;
    if (last != null && now.difference(last.end) <= mergeGap) {
      last.end = now;
    } else {
      d.sessions.add(DeviceSession(now, now, address ?? ''));
      if (d.sessions.length > maxSessions) d.sessions.removeAt(0);
      fresh = true;
    }
    d.lastSeen = now;
    return fresh;
  }

  /// Known devices, most recently seen first.
  List<DeviceProfile> get sorted => profiles.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

  void forget(String fp) => profiles.remove(fp);

  Future<void> _pending = Future<void>.value();

  Future<void> save() => _pending = _pending.then((_) async {
        try {
          await _file.parent.create(recursive: true);
          await _file.writeAsString(jsonEncode({for (final e in profiles.entries) e.key: e.value.toJson()}));
        } catch (_) {}
      });
}
