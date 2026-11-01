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

/// Protects the identity seed at rest with an OS key store
/// (Android Keystore, Windows DPAPI, …). Without one, the seed is stored in a
/// file readable only by the current user (like an SSH private key).
abstract class SeedVault {
  /// Stored in identity.json so a blob is only opened by the vault that made it.
  String get id;
  Future<List<int>> seal(List<int> secret);
  Future<List<int>> open(List<int> sealed);
}

/// Long-term device identity: an Ed25519 key pair generated on first run
/// and stored locally. The fingerprint is what users trust.
class DeviceIdentity {
  DeviceIdentity._(this.keyPair, this.publicKey, this.name, this._file, this._seed, this._vault)
      : fingerprint = fingerprintOf(publicKey);

  final SimpleKeyPair keyPair;
  final List<int> publicKey;
  final String fingerprint;
  String name;
  final File _file;
  final List<int> _seed;
  final SeedVault? _vault;

  /// True when a stored identity existed but could not be opened (for
  /// example the OS key store was reset), so a new one was generated.
  bool regenerated = false;

  /// How the private key is protected on disk: 'file', or the vault id.
  String protection = 'file';

  String get shortId => fingerprint.substring(0, 8);

  static Future<DeviceIdentity> loadOrCreate(Directory dir, {SeedVault? vault}) async {
    await _securePermissions(dir, directory: true);
    final file = File(p.join(dir.path, 'identity.json'));
    List<int>? storedSeed;
    String? storedName;
    var unreadable = false;
    if (await file.exists()) {
      try {
        final m = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        storedName = m['name'] as String?;
        if (m['sealed'] != null) {
          final vaultId = m['vault'] as String?;
          if (vault != null && vault.id == vaultId) {
            storedSeed = await vault.open(base64Decode(m['sealed'] as String));
          }
        } else if (m['seed'] != null) {
          storedSeed = base64Decode(m['seed'] as String);
        }
        if (storedSeed == null || storedSeed.length != 32) {
          unreadable = true;
          storedSeed = null;
        }
      } catch (_) {
        unreadable = true;
        storedSeed = null;
      }
      if (unreadable) {
        // Keep the old file around for forensics instead of overwriting it.
        try {
          await file.copy('${file.path}.unreadable-${DateTime.now().millisecondsSinceEpoch}');
        } catch (_) {}
      }
    }
    final List<int> seed;
    if (storedSeed != null) {
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
      vault,
    )..regenerated = unreadable;
    await identity._save();
    return identity;
  }

  Future<void> rename(String newName) async {
    name = sanitizeDeviceName(newName);
    await _save();
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    Map<String, Object?> body = {'v': 1, 'seed': base64Encode(_seed), 'name': name};
    protection = 'file';
    final vault = _vault;
    if (vault != null) {
      try {
        final sealed = await vault.seal(_seed);
        body = {'v': 2, 'vault': vault.id, 'sealed': base64Encode(sealed), 'name': name};
        protection = vault.id;
      } catch (_) {
        // Key store unavailable: fall back to an owner-only file.
      }
    }
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(body), flush: true);
    await _securePermissions(tmp);
    await tmp.rename(_file.path);
  }

  static String _defaultName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iPhone';
    try {
      return Platform.localHostname;
    } catch (_) {
      return platformName();
    }
  }
}

Future<void> _securePermissions(FileSystemEntity entity, {bool directory = false}) async {
  if (!(Platform.isLinux || Platform.isMacOS)) return;
  try {
    if (directory) await (entity as Directory).create(recursive: true);
    await Process.run('chmod', [directory ? '700' : '600', entity.path]);
  } catch (_) {}
}

class KnownDevice {
  const KnownDevice({required this.fingerprint, required this.name, required this.addedAt});

  factory KnownDevice.fromJson(Map<String, dynamic> m) => KnownDevice(
        fingerprint: m['fp'] as String,
        name: m['name'] as String,
        addedAt: DateTime.parse(m['addedAt'] as String),
      );

  final String fingerprint;
  final String name;
  final DateTime addedAt;

  Map<String, Object> toJson() => {'fp': fingerprint, 'name': name, 'addedAt': addedAt.toIso8601String()};
}

typedef TrustedDevice = KnownDevice;

/// Devices the user trusts (verified once by code or QR) and devices the
/// user blocked (their requests are declined without asking).
class TrustStore {
  TrustStore._(this._trustedFile, this._blockedFile, this._trusted, this._blocked);

  final File _trustedFile;
  final File _blockedFile;
  final Map<String, KnownDevice> _trusted;
  final Map<String, KnownDevice> _blocked;

  static Future<Map<String, KnownDevice>> _read(File file) async {
    final items = <String, KnownDevice>{};
    if (await file.exists()) {
      try {
        final list = jsonDecode(await file.readAsString()) as List<dynamic>;
        for (final e in list) {
          final d = KnownDevice.fromJson(e as Map<String, dynamic>);
          items[d.fingerprint] = d;
        }
      } catch (_) {}
    }
    return items;
  }

  static Future<TrustStore> load(Directory dir) async {
    final trusted = File(p.join(dir.path, 'trusted.json'));
    final blocked = File(p.join(dir.path, 'blocked.json'));
    return TrustStore._(trusted, blocked, await _read(trusted), await _read(blocked));
  }

  bool isTrusted(String fingerprint) => _trusted.containsKey(fingerprint);
  bool isBlocked(String fingerprint) => _blocked.containsKey(fingerprint);

  List<KnownDevice> get all => _sorted(_trusted);
  List<KnownDevice> get blocked => _sorted(_blocked);

  static List<KnownDevice> _sorted(Map<String, KnownDevice> m) =>
      m.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  Future<void> add(String fingerprint, String name) async {
    _blocked.remove(fingerprint);
    _trusted[fingerprint] = KnownDevice(fingerprint: fingerprint, name: name, addedAt: DateTime.now());
    await _save();
  }

  Future<void> remove(String fingerprint) async {
    _trusted.remove(fingerprint);
    await _save();
  }

  Future<void> block(String fingerprint, String name) async {
    _trusted.remove(fingerprint);
    _blocked[fingerprint] = KnownDevice(fingerprint: fingerprint, name: name, addedAt: DateTime.now());
    await _save();
  }

  Future<void> unblock(String fingerprint) async {
    _blocked.remove(fingerprint);
    await _save();
  }

  Future<void> _save() async {
    await _trustedFile.parent.create(recursive: true);
    await _trustedFile.writeAsString(jsonEncode(_trusted.values.map((d) => d.toJson()).toList()), flush: true);
    await _blockedFile.writeAsString(jsonEncode(_blocked.values.map((d) => d.toJson()).toList()), flush: true);
  }
}
