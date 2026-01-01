import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Win32 DATA_BLOB structure used by CryptProtectData / CryptUnprotectData.
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptProtectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer pReserved,
  Pointer pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);
typedef _CryptProtectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer pReserved,
  Pointer pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer pReserved,
  Pointer pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);
typedef _CryptUnprotectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer pReserved,
  Pointer pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _LocalFreeNative = Pointer Function(Pointer hMem);
typedef _LocalFreeDart = Pointer Function(Pointer hMem);

/// Direct FFI access to Windows DPAPI (crypt32.dll).
///
/// Replaces the PowerShell-subprocess approach that spawned 2-5 processes
/// per daemon startup (2-5s CLR JIT each). FFI calls complete in <1ms.
class DpapiFfi {
  static DpapiFfi? _instance;

  late final _CryptProtectDataDart _cryptProtectData;
  late final _CryptUnprotectDataDart _cryptUnprotectData;
  late final _LocalFreeDart _localFree;

  DpapiFfi._() {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');

    _cryptProtectData = crypt32.lookupFunction<
        _CryptProtectDataNative, _CryptProtectDataDart>('CryptProtectData');

    _cryptUnprotectData = crypt32.lookupFunction<
        _CryptUnprotectDataNative, _CryptUnprotectDataDart>(
        'CryptUnprotectData');

    _localFree = kernel32
        .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  }

  static DpapiFfi get instance => _instance ??= DpapiFfi._();

  /// Encrypt [data] using DPAPI (CurrentUser scope).
  /// Returns the encrypted bytes, or null on failure.
  Uint8List? protect(Uint8List data) {
    final pDataIn = calloc<_DataBlob>();
    final pDataOut = calloc<_DataBlob>();
    Pointer<Uint8>? inputBuf;

    try {
      inputBuf = calloc<Uint8>(data.length);
      for (var i = 0; i < data.length; i++) {
        inputBuf[i] = data[i];
      }
      pDataIn.ref.cbData = data.length;
      pDataIn.ref.pbData = inputBuf;

      pDataOut.ref.cbData = 0;
      pDataOut.ref.pbData = nullptr.cast();

      final ok = _cryptProtectData(
        pDataIn,
        nullptr.cast(), // no description
        nullptr.cast(), // no entropy
        nullptr, // reserved
        nullptr, // no prompt
        0, // CRYPTPROTECT_UI_FORBIDDEN is 0x1 but we pass 0 for CurrentUser
        pDataOut,
      );

      if (ok == 0) return null;

      final outLen = pDataOut.ref.cbData;
      final outPtr = pDataOut.ref.pbData;
      if (outLen == 0 || outPtr == nullptr.cast<Uint8>()) return null;

      final result = Uint8List(outLen);
      for (var i = 0; i < outLen; i++) {
        result[i] = outPtr[i];
      }
      return result;
    } finally {
      if (pDataOut.ref.pbData != nullptr.cast<Uint8>()) {
        _localFree(pDataOut.ref.pbData.cast());
      }
      if (inputBuf != null) calloc.free(inputBuf);
      calloc.free(pDataIn);
      calloc.free(pDataOut);
    }
  }

  /// Decrypt DPAPI-protected [data] (CurrentUser scope).
  /// Returns the plaintext bytes, or null on failure.
  Uint8List? unprotect(Uint8List data) {
    final pDataIn = calloc<_DataBlob>();
    final pDataOut = calloc<_DataBlob>();
    Pointer<Uint8>? inputBuf;

    try {
      inputBuf = calloc<Uint8>(data.length);
      for (var i = 0; i < data.length; i++) {
        inputBuf[i] = data[i];
      }
      pDataIn.ref.cbData = data.length;
      pDataIn.ref.pbData = inputBuf;

      pDataOut.ref.cbData = 0;
      pDataOut.ref.pbData = nullptr.cast();

      final ok = _cryptUnprotectData(
        pDataIn,
        nullptr.cast(), // no description out
        nullptr.cast(), // no entropy
        nullptr, // reserved
        nullptr, // no prompt
        0, // flags
        pDataOut,
      );

      if (ok == 0) return null;

      final outLen = pDataOut.ref.cbData;
      final outPtr = pDataOut.ref.pbData;
      if (outLen == 0 || outPtr == nullptr.cast<Uint8>()) return null;

      final result = Uint8List(outLen);
      for (var i = 0; i < outLen; i++) {
        result[i] = outPtr[i];
      }
      return result;
    } finally {
      if (pDataOut.ref.pbData != nullptr.cast<Uint8>()) {
        _localFree(pDataOut.ref.pbData.cast());
      }
      if (inputBuf != null) calloc.free(inputBuf);
      calloc.free(pDataIn);
      calloc.free(pDataOut);
    }
  }
}
