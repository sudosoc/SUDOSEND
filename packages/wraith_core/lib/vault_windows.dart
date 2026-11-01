// Windows DPAPI (CryptProtectData) seed vault. The sealed blob can only be
// opened by the same Windows user account on the same machine.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'identity.dart';
import 'models.dart';

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(
    Pointer<_DataBlob>, Pointer<Void>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>);
typedef _CryptDart = int Function(
    Pointer<_DataBlob>, Pointer<Void>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>);
typedef _LocalFree = Pointer<Void> Function(Pointer<Void>);

const int _cryptprotectUiForbidden = 0x1;

class DpapiVault implements SeedVault {
  static bool get supported => Platform.isWindows;

  @override
  String get id => 'dpapi';

  late final DynamicLibrary _crypt32 = DynamicLibrary.open('crypt32.dll');
  late final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  late final _CryptDart _protect = _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptProtectData');
  late final _CryptDart _unprotect = _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptUnprotectData');
  late final _LocalFree _localFree = _kernel32.lookupFunction<_LocalFree, _LocalFree>('LocalFree');

  @override
  Future<List<int>> seal(List<int> secret) async => _run(secret, protect: true);

  @override
  Future<List<int>> open(List<int> sealed) async => _run(sealed, protect: false);

  Uint8List _run(List<int> data, {required bool protect}) {
    final input = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    final buffer = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final description = 'SUDOSEND identity'.toNativeUtf16();
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = buffer;
      final ok = (protect ? _protect : _unprotect)(
        input,
        protect ? description.cast<Void>() : nullptr,
        nullptr,
        nullptr,
        nullptr,
        _cryptprotectUiForbidden,
        output,
      );
      if (ok == 0) throw WraithException('DPAPI ${protect ? 'protect' : 'unprotect'} failed');
      final result = Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      _localFree(output.ref.pbData.cast<Void>());
      return result;
    } finally {
      buffer.asTypedList(data.length).fillRange(0, data.length, 0);
      calloc.free(buffer);
      calloc.free(input);
      calloc.free(output);
      calloc.free(description);
    }
  }
}
