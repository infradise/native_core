import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform/windows/windows_window_finder.dart';
import 'window.dart';

final WindowsMainWindowCache<Window> _windowsMainWindowCache =
    WindowsMainWindowCache<Window>();

/// Returns the application's primary desktop [Window], or `null` before the
/// first window is created or inside headless Dart VM / widget tests.
///
/// * **Windows**: Resolves the current process's `FLUTTER_RUNNER_WIN32_WINDOW`
///   handle directly so `SW_HIDE` (Close-to-Tray) and unfocused states never
///   return `null` or a secondary popup window.
/// * **macOS / Linux**: Delegates to `WindowManager.instance.getCurrent()`.
Window? get mainWindow {
  try {
    if (Platform.isWindows) {
      return _windowsMainWindowCache.resolve(
        findHandle: findCurrentProcessFlutterWindowHandle,
        isHandleAlive: isWindowsNativeWindowAlive,
        wrapHandle: Window.createWithNativeWindow,
        lookupRegistered: (probe) => WindowManager.instance.get(probe.id),
        sameBackingHandle: (a, b) => a.nativeHandle == b.nativeHandle,
        disposeProbe: (probe) => probe.dispose(),
      );
    }
    return WindowManager.instance.getCurrent();
  } on ArgumentError {
    return null;
  }
}

/// Pure, testable resolution and lifetime cache for the Windows main `HWND`.
@visibleForTesting
class WindowsMainWindowCache<W extends Object> {
  /// Creates an empty [WindowsMainWindowCache].
  WindowsMainWindowCache();

  Pointer<Void>? _cachedHandle;
  W? _cachedWindow;

  /// Resolves and caches the process's primary window instance while its
  /// backing `HWND` remains alive, re-resolving automatically if destroyed.
  W? resolve({
    required Pointer<Void>? Function() findHandle,
    required bool Function(Pointer<Void> handle) isHandleAlive,
    required W? Function(Pointer<Void> handle) wrapHandle,
    required W? Function(W probe) lookupRegistered,
    required bool Function(W a, W b) sameBackingHandle,
    required void Function(W probe) disposeProbe,
  }) {
    final existingWindow = _cachedWindow;
    final existingHandle = _cachedHandle;
    if (existingWindow != null &&
        existingHandle != null &&
        isHandleAlive(existingHandle)) {
      return existingWindow;
    }

    _cachedWindow = null;
    _cachedHandle = null;

    final hwnd = findHandle();
    if (hwnd == null || hwnd == nullptr) return null;

    final probe = wrapHandle(hwnd);
    if (probe == null) return null;

    final registered = lookupRegistered(probe);
    if (registered != null) {
      if (!sameBackingHandle(registered, probe)) {
        disposeProbe(probe);
      }
      _cachedHandle = hwnd;
      _cachedWindow = registered;
      return registered;
    }

    _cachedHandle = hwnd;
    _cachedWindow = probe;
    return probe;
  }
}
