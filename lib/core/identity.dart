import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import 'util.dart';

/// 128-bit fingerprint of an Ed25519 identity key, uppercase hex.
String fingerprintOf(List<int> publicKey) =>
    crypto.sha256.convert(publicKey).toString().substring(0, 32).toUpperCase();

/// Long-term device identity: an Ed25519 key pair generated on first run
/// and stored locally. The fingerprint is what users trust.
class DeviceIdentity {
  DeviceIdentity._(this.keyPair, this.publicKey, this.name, this._file, this._seed)
      : fingerprint = fingerprintOf(publicKey);

  final SimpleKeyPair keyPair;
  final List<int> publicKey;
  final String fingerprint;
  String name;
  final File _file;
  final List<int> _seed;

  String get shortId => fingerprint.substring(0, 8);

  static Future<DeviceIdentity> loadOrCreate(Directory dir) async {
    final file = File(p.join(dir.path, 'identity.json'));
    List<int>? storedSeed;
    String? storedName;
    if (await file.exists()) {
      try {
        final m = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        storedSeed = base64Decode(m['seed'] as String);
        storedName = m['name'] as String?;
      } catch (_) {
        // Corrupt file: fall through and generate a fresh identity.
      }
    }
    final List<int> seed;
    if (storedSeed != null && storedSeed.length == 32) {
      seed = storedSeed;
    } else {
      final rng = Random.secure();
      seed = List<int>.generate(32, (_) => rng.nextInt(256));
    }
    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKey = (await keyPair.extractPublicKey()).bytes;
    final identity = DeviceIdentity._(
      keyPair,
      publicKey,
      sanitizeDeviceName(storedName ?? _defaultName()),
      file,
      seed,
    );
    await identity._save();
    return identity;
  }

  Future<void> rename(String newName) async {
    name = sanitizeDeviceName(newName);
    await _save();
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({'v': 1, 'seed': base64Encode(_seed), 'name': name}),
      flush: true,
    );
    if (Platform.isLinux || Platform.isMacOS) {
      // Private key material: owner read/write only.
      try {
        await Process.run('chmod', ['600', _file.path]);
      } catch (_) {}
    }
  }

  static String _defaultName() {
    if (Platform.isAndroid) return 'Android';
    try {
      return Platform.localHostname;
    } catch (_) {
      return platformName();
    }
  }
}

class TrustedDevice {
  const TrustedDevice({required this.fingerprint, required this.name, required this.addedAt});

  factory TrustedDevice.fromJson(Map<String, dynamic> m) => TrustedDevice(
        fingerprint: m['fp'] as String,
        name: m['name'] as String,
        addedAt: DateTime.parse(m['addedAt'] as String),
      );

  final String fingerprint;
  final String name;
  final DateTime addedAt;

  Map<String, Object> toJson() =>
      {'fp': fingerprint, 'name': name, 'addedAt': addedAt.toIso8601String()};
}

/// Devices whose fingerprint the user has verified once (via the SAS code).
class TrustStore {
  TrustStore._(this._file, this._items);

  final File _file;
  final Map<String, TrustedDevice> _items;

  static Future<TrustStore> load(Directory dir) async {
    final file = File(p.join(dir.path, 'trusted.json'));
    final items = <String, TrustedDevice>{};
    if (await file.exists()) {
      try {
        final list = jsonDecode(await file.readAsString()) as List<dynamic>;
        for (final e in list) {
          final d = TrustedDevice.fromJson(e as Map<String, dynamic>);
          items[d.fingerprint] = d;
        }
      } catch (_) {}
    }
    return TrustStore._(file, items);
  }

  bool isTrusted(String fingerprint) => _items.containsKey(fingerprint);

  List<TrustedDevice> get all =>
      _items.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  Future<void> add(String fingerprint, String name) async {
    _items[fingerprint] =
        TrustedDevice(fingerprint: fingerprint, name: name, addedAt: DateTime.now());
    await _save();
  }

  Future<void> remove(String fingerprint) async {
    _items.remove(fingerprint);
    await _save();
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(_items.values.map((d) => d.toJson()).toList()),
        flush: true);
  }
}
