import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

String platformName() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isIOS) return 'ios';
  return 'unknown';
}

String sanitizeDeviceName(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  if (cleaned.isEmpty) return 'Unknown device';
  return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
}

const _windowsReserved = {
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Turns an untrusted, peer-supplied file name into a safe basename.
/// Blocks path traversal (../), absolute paths, control characters,
/// characters Windows rejects, and reserved device names.
String sanitizeFileName(String input) {
  var name = input.replaceAll('\\', '/').split('/').last;
  name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"|?*]'), '_');
  name = name.replaceAll(RegExp(r'^[. ]+'), '');
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) name = 'file';
  final stem = name.split('.').first.toUpperCase();
  if (_windowsReserved.contains(stem)) name = '_$name';
  if (name.length > 200) {
    final ext = p.extension(name);
    final keep = ext.length < 20 ? ext : '';
    name = name.substring(0, 200 - keep.length) + keep;
  }
  return name;
}

/// Returns a file in [dir] named [name] that does not exist yet:
/// photo.jpg → photo (1).jpg → photo (2).jpg …
Future<File> uniqueFile(Directory dir, String name) async {
  final stem = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  var candidate = File(p.join(dir.path, name));
  var i = 1;
  while (await candidate.exists()) {
    candidate = File(p.join(dir.path, '$stem ($i)$ext'));
    i++;
  }
  return candidate;
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[i]}';
}

String formatSpeed(double bytesPerSecond) => '${formatBytes(max(0, bytesPerSecond))}/s';

/// A1B2C3D4E5F6… → A1B2 C3D4 E5F6 …
String groupFingerprint(String fp, {int groups = 8}) {
  final parts = <String>[];
  for (var i = 0; i + 4 <= fp.length && parts.length < groups; i += 4) {
    parts.add(fp.substring(i, i + 4));
  }
  return parts.join(' ');
}

String formatSas(String sas) =>
    sas.length == 6 ? '${sas.substring(0, 3)} ${sas.substring(3)}' : sas;
