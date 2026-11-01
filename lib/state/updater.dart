import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Public repository the builds are published to (the source repo is private).
const String kReleaseRepo = 'sudosoc/SUDOSEND-APP';
const String kReleasePage = 'https://github.com/$kReleaseRepo/releases/latest';
const String kLinuxInstallCommand = 'curl -fsSL https://raw.githubusercontent.com/$kReleaseRepo/main/get.sh | bash';

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, this.size, this.sha256);
  final String name;
  final String url;
  final int size;

  /// Hex SHA-256 published by GitHub for the asset, when available.
  final String? sha256;
}

class UpdateInfo {
  const UpdateInfo({required this.version, required this.notes, required this.page, required this.assets});
  final String version; // "0.8.0"
  final String notes;
  final String page;
  final List<ReleaseAsset> assets;

  ReleaseAsset? asset(String name) => assets.where((a) => a.name == name).firstOrNull;
}

/// How this platform installs an update.
enum UpdateMethod {
  /// Download the APK and hand it to the Android installer.
  androidApk,

  /// Download the Windows installer and run it.
  windowsInstaller,

  /// Download a package into Downloads and show it (portable Windows, macOS).
  downloadAndReveal,

  /// Show the one-line installer (Linux: .deb or portable, handled by get.sh).
  linuxCommand,

  /// Open the release page (iOS sideloading).
  openPage,
}

class Updater {
  Updater(this.currentVersion);
  final String currentVersion;

  /// Fetches the latest published release. Throws on network errors.
  Future<UpdateInfo> latest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$kReleaseRepo/releases/latest'));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'SUDOSEND/$currentVersion');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) throw const HttpException('No release published yet');
      if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}');
      final m = jsonDecode(body) as Map<String, dynamic>;
      final tag = (m['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
      return UpdateInfo(
        version: tag,
        notes: m['body'] as String? ?? '',
        page: m['html_url'] as String? ?? kReleasePage,
        assets: [
          for (final a in (m['assets'] as List<dynamic>? ?? const []))
            if (a is Map<String, dynamic>)
              ReleaseAsset(
                a['name'] as String,
                a['browser_download_url'] as String,
                a['size'] as int? ?? 0,
                _digest(a['digest']),
              ),
        ],
      );
    } finally {
      client.close(force: true);
    }
  }

  static String? _digest(Object? raw) {
    if (raw is! String || !raw.startsWith('sha256:')) return null;
    return raw.substring(7).toLowerCase();
  }

  /// True if [remote] ("0.8.0") is newer than [local] ("0.7.0").
  static bool isNewer(String remote, String local) {
    List<int> parse(String v) => v.split(RegExp(r'[.+-]')).take(3).map((x) => int.tryParse(x) ?? 0).toList();
    final a = parse(remote), b = parse(local);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static UpdateMethod get method {
    if (Platform.isAndroid) return UpdateMethod.androidApk;
    if (Platform.isWindows) return _windowsInstalled ? UpdateMethod.windowsInstaller : UpdateMethod.downloadAndReveal;
    if (Platform.isMacOS) return UpdateMethod.downloadAndReveal;
    if (Platform.isLinux) return UpdateMethod.linuxCommand;
    return UpdateMethod.openPage;
  }

  /// The Inno Setup installer leaves an uninstaller next to the exe.
  static bool get _windowsInstalled =>
      File(p.join(p.dirname(Platform.resolvedExecutable), 'unins000.exe')).existsSync();

  /// The file this device needs from [info], or null.
  static ReleaseAsset? pick(UpdateInfo info, {String androidAbi = ''}) {
    if (Platform.isAndroid) {
      return info.asset('sudosend-android-$androidAbi.apk') ?? info.asset('sudosend-android-universal.apk');
    }
    if (Platform.isWindows) {
      return info.asset(_windowsInstalled ? 'sudosend-windows-x64-setup.exe' : 'sudosend-windows-x64-portable.zip');
    }
    if (Platform.isMacOS) return info.asset('sudosend-macos.zip');
    if (Platform.isLinux) {
      final deb = Abi.current() == Abi.linuxArm64 ? 'arm64' : 'amd64';
      return info.asset('sudosend_${info.version}_$deb.deb');
    }
    return null;
  }

  /// Downloads [asset] into [dir], reporting progress 0..1, and checks the
  /// SHA-256 GitHub publishes for it. Throws if the file is corrupted.
  static Future<File> download(ReleaseAsset asset, Directory dir,
      {void Function(double progress)? onProgress, bool Function()? cancelled}) async {
    await dir.create(recursive: true);
    final dest = File(p.join(dir.path, asset.name));
    // Already downloaded (e.g. the user had to allow installs first)?
    if (await dest.exists() && await dest.length() == asset.size) {
      final hex = (await sha256.bind(dest.openRead()).first).toString();
      if (asset.sha256 == null || hex == asset.sha256) return dest;
    }
    final part = File('${dest.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(asset.url));
      req.headers.set(HttpHeaders.userAgentHeader, 'SUDOSEND');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('Download failed (${res.statusCode})');
      final total = res.contentLength > 0 ? res.contentLength : asset.size;
      final sink = part.openWrite();
      final hasher = AccumulatorSink<Digest>();
      final hashInput = sha256.startChunkedConversion(hasher);
      var got = 0;
      try {
        await for (final chunk in res) {
          if (cancelled?.call() ?? false) throw const HttpException('Cancelled');
          sink.add(chunk);
          hashInput.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress?.call(got / total);
        }
      } finally {
        await sink.close();
      }
      hashInput.close();
      final hex = hasher.events.single.toString();
      if (asset.sha256 != null && hex != asset.sha256) {
        await part.delete();
        throw const HttpException('The download is corrupted (SHA-256 mismatch) — try again');
      }
      if (await dest.exists()) await dest.delete();
      return await part.rename(dest.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}

/// Minimal sink that collects the digest (avoids a dependency on package:convert).
class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];
  @override
  void add(T event) => events.add(event);
  @override
  void close() {}
}
