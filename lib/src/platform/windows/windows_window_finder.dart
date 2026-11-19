import 'dart:ffi' as ffi;
import 'dart:io';

import '../../diagnostics.dart';
import '../../ffi/native_memory.dart';
import 'windows_win32_bindings.dart';

/// Win32 window class name registered by the stock Flutter Windows runner
/// (`windows/runner/win32_window.cpp` `kWindowClassName`).
const String kFlutterWin32WindowClassName = 'FLUTTER_RUNNER_WIN32_WINDOW';

/// Finds this process's top-level `FLUTTER_RUNNER_WIN32_WINDOW` `HWND` on
/// Windows, even when the window is hidden (`SW_HIDE`, e.g. minimized to the
/// system tray) or unfocused.
///
/// Returns `null` on non-Windows platforms or in headless `flutter_tester.exe`
/// runs where no runner window exists.
ffi.Pointer<ffi.Void>? findCurrentProcessFlutterWindowHandle() {
  if (!Platform.isWindows) return null;
  final win32 = WindowsWin32Bindings.instance;
  if (win32 == null) return null;

  try {
    return NativeMemory.withUtf16WString(kFlutterWin32WindowClassName, (
      classPtr,
    ) {
      final pidPtr = win32.scratchUint32Pair;
      final selfPid = win32.getCurrentProcessId();

      var childAfter = ffi.nullptr.cast<ffi.Void>();
      while (true) {
        final candidate = win32.findWindowExW(
          ffi.nullptr,
          childAfter,
          classPtr,
          ffi.nullptr,
        );
        if (candidate == ffi.nullptr) return null;
        pidPtr.value = 0;
        win32.getWindowThreadProcessId(candidate, pidPtr);
        if (pidPtr.value == selfPid && win32.isWindow(candidate) != 0) {
          return candidate;
        }
        childAfter = candidate;
      }
    });
  } catch (error, stackTrace) {
    NativeCoreDiagnostics.report(
      'findCurrentProcessFlutterWindowHandle',
      error,
      stackTrace,
    );
    return null;
  }
}

/// Returns whether [hwnd] still refers to a live Win32 `HWND`.
bool isWindowsNativeWindowAlive(ffi.Pointer<ffi.Void> hwnd) {
  if (!Platform.isWindows || hwnd == ffi.nullptr) return false;
  final win32 = WindowsWin32Bindings.instance;
  if (win32 == null) return false;
  try {
    return win32.isWindow(hwnd) != 0;
  } catch (error, stackTrace) {
    NativeCoreDiagnostics.report(
      'isWindowsNativeWindowAlive',
      error,
      stackTrace,
    );
    return false;
  }
}
