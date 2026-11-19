import 'dart:convert' show Utf8Codec;
import 'dart:ffi' as ffi;

/// Shared C heap allocation and string marshaling helpers for `native_core`.
///
/// Resolves `malloc` and `free` once from the host process symbol table and
/// enforces strict UTF-8 (`Pointer<Char>`) vs UTF-16 (`Pointer<Uint16>`)
/// encoding with embedded NUL stripping.
abstract final class NativeMemory {
  static const Utf8Codec _utf8 = Utf8Codec(allowMalformed: true);

  static final ffi.DynamicLibrary _process = ffi.DynamicLibrary.process();

  /// Allocates `byteCount` raw bytes on the native C heap.
  static final ffi.Pointer<ffi.Void> Function(int byteCount) malloc = _process
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Size),
        ffi.Pointer<ffi.Void> Function(int)
      >('malloc');

  /// Frees a native C heap pointer previously returned by [malloc].
  static final void Function(ffi.Pointer<ffi.Void> pointer) free = _process
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)
      >('free');

  /// Fills [byteCount] bytes starting at [ptr] with zeroes.
  static void zeroFill(ffi.Pointer<ffi.Void> ptr, int byteCount) {
    if (ptr == ffi.nullptr || byteCount <= 0) return;
    final bytes = ptr.cast<ffi.Uint8>();
    for (var i = 0; i < byteCount; i++) {
      bytes[i] = 0;
    }
  }

  /// Encodes [value] as a NUL-terminated UTF-8 C string (`Pointer<Char>`),
  /// executes [action], and frees the temporary buffer in `finally`.
  static T withUtf8CString<T>(
    String value,
    T Function(ffi.Pointer<ffi.Char> cstr) action,
  ) {
    final sanitized =
        value.contains('\u0000') ? value.replaceAll('\u0000', '') : value;
    final bytes = _utf8.encode(sanitized);
    final raw = malloc(bytes.length + 1).cast<ffi.Uint8>();
    if (raw == ffi.nullptr) {
      throw StateError(
        'malloc failed for UTF-8 C string (${bytes.length + 1}B)',
      );
    }
    try {
      for (var i = 0; i < bytes.length; i++) {
        raw[i] = bytes[i];
      }
      raw[bytes.length] = 0;
      return action(raw.cast<ffi.Char>());
    } finally {
      free(raw.cast());
    }
  }

  /// Encodes [value] as a NUL-terminated UTF-16LE wide string
  /// (`Pointer<Uint16>`), executes [action], and frees the temporary buffer in
  /// `finally`.
  static T withUtf16WString<T>(
    String value,
    T Function(ffi.Pointer<ffi.Uint16> wstr) action,
  ) {
    final sanitized =
        value.contains('\u0000') ? value.replaceAll('\u0000', '') : value;
    final units = sanitized.codeUnits;
    final raw = malloc((units.length + 1) * 2).cast<ffi.Uint16>();
    if (raw == ffi.nullptr) {
      throw StateError(
        'malloc failed for UTF-16 string (${units.length + 1} units)',
      );
    }
    try {
      for (var i = 0; i < units.length; i++) {
        raw[i] = units[i];
      }
      raw[units.length] = 0;
      return action(raw);
    } finally {
      free(raw.cast());
    }
  }
}
