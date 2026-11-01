// Free / total space of the volume holding a path (desktop platforms).
// Android asks the OS through the app's native bridge instead.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _GetFreeNative = Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetFreeDart = int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

/// (free bytes available to this user, total bytes), or null if unknown.
Future<(int, int)?> diskSpace(String path) async {
  try {
    if (Platform.isWindows) return _windows(path);
    if (Platform.isLinux || Platform.isMacOS) return await _df(path);
  } catch (_) {}
  return null;
}

(int, int)? _windows(String path) {
  final k32 = DynamicLibrary.open('kernel32.dll');
  final fn = k32.lookupFunction<_GetFreeNative, _GetFreeDart>('GetDiskFreeSpaceExW');
  final p = path.toNativeUtf16();
  final avail = calloc<Uint64>();
  final total = calloc<Uint64>();
  final free = calloc<Uint64>();
  try {
    if (fn(p, avail, total, free) == 0) return null;
    return (avail.value, total.value);
  } finally {
    calloc.free(p);
    calloc.free(avail);
    calloc.free(total);
    calloc.free(free);
  }
}

Future<(int, int)?> _df(String path) async {
  final r = await Process.run('df', ['-Pk', path]);
  if (r.exitCode != 0) return null;
  final lines = (r.stdout as String).trim().split('\n');
  if (lines.length < 2) return null;
  // Filesystem 1024-blocks Used Available Capacity Mounted-on (name may contain spaces).
  final cols = lines.last.trim().split(RegExp(r'\s+'));
  if (cols.length < 6) return null;
  final n = cols.length;
  final total = int.tryParse(cols[n - 5]);
  final avail = int.tryParse(cols[n - 3]);
  if (total == null || avail == null) return null;
  return (avail * 1024, total * 1024);
}
