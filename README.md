# native_core

[![Pub Version](https://img.shields.io/pub/v/native_core)](https://pub.dev/packages/native_core)
[![Dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen)](https://pub.dev/packages/native_core)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/infradise/native_core/blob/main/LICENSE)

Zero-dependency desktop window, display, and single-instance lifecycle primitives for Flutter across **Linux**, **macOS**, and **Windows**.

`native_core` replaces `nativeapi`, `window_manager`, and `screen_retriever` with pure `dart:ffi` bindings to OS system libraries and **zero external hosted dependencies** — requiring zero modifications to stock `flutter create` host runner files.

| Platform | Support | Implementation |
| :--- | :--- | :--- |
| Linux | GTK 3.24+ (`X11` & `Wayland`) | `libgtk-3.so.0`, `libgdk-3.so.0`, `libgobject-2.0.so.0`, `libgio-2.0.so.0` |
| macOS | macOS 13.0+ (`arm64` & `x86_64`) | `/usr/lib/libobjc.A.dylib`, `AppKit`, `CoreGraphics` |
| Windows | Windows 10 / 11 (`x64` & `arm64`) | `user32.dll`, `comctl32.dll`, `dwmapi.dll`, `gdi32.dll`, `shcore.dll`, `kernel32.dll` |

## Platform Capability Matrix

| Capability | Linux (`GTK3`) | macOS (`AppKit`) | Windows (`Win32`) |
| :--- | :---: | :---: | :---: |
| Custom frameless window (`TitleBarStyle.hidden`) | ✅ (`hideLinuxNativeTitleBar`) | ✅ (`FullSizeContentView`) | ✅ (`SetWindowSubclass` + DWM) |
| Hidden/tray window resolution & foreground focus | ✅ (X11 server time) | ✅ (`activate` + `orderFrontRegardless`) | ✅ (`FLUTTER_RUNNER_WIN32_WINDOW` + `AttachThreadInput`) |
| Multi-monitor `bounds`, `workArea`, DPI `scaleFactor` | ✅ (`GdkMonitor`) | ✅ (`NSScreen` + `CoreGraphics` fallback) | ✅ (`EnumDisplayMonitors` + `GetDpiForMonitor`) |
| Single-instance guard + secondary IPC (`ensureSingleInstance`) | ✅ (Unix Domain Socket) | ✅ (Unix Domain Socket) | ✅ (Named Mutex + `WM_COPYDATA`) |
| Interactive window drag (`startPlatformWindowDragging`) | ✅ (with `GDK_BUTTON_RELEASE`) | ✅ (`performWindowDragWithEvent:`) | ✅ (`WM_NCLBUTTONDOWN` / `HTCAPTION`) |
| Native erase background brush (`backgroundColor`) | Stored in memory | Stored in memory | ✅ (GDI brush on `WM_ERASEBKGND`) |
| Native window system menu (`showSystemMenu`) | Returns `false` | Returns `false` | ✅ (`GetSystemMenu` + `TrackPopupMenu`) |

## Features

- **Zero External Dependencies**: Depends exclusively on the Flutter SDK (`flutter`).
- **Self-Contained Custom Frameless Windows (`TitleBarStyle.hidden`)**:
  - **Windows**: `SetWindowSubclass` handles `WM_NCCALCSIZE`, DWM shadow & rounded corners, 8-direction resize hit-testing (preserving Fitts's Law top-right corner clicks when maximized), `WM_GETMINMAXINFO` `minimumSize` enforcement, `WM_ERASEBKGND` `WHITE_BRUSH` flash suppression without live DXGI resize strobe flicker, and `WM_WINDOWPOSCHANGING` coordination with stock `flutter_window.cpp` (`SetNextFrameCallback`).
  - **macOS**: Combines `NSWindowTitleHidden`, `setTitlebarAppearsTransparent:YES`, and `NSWindowStyleMaskFullSizeContentView` (`1 << 15`), with Hot Restart-safe `NativeCoreWindowDelegate` method rebinding.
  - **Linux**: Directly hides `GtkHeaderBar` (`hideLinuxNativeTitleBar`) without adding 132px CSD shadow gutters on Wayland, and synthesizes `GDK_BUTTON_RELEASE` after native grabs (`startPlatformWindowDragging`, `showPlatformWindowSystemMenu`).
- **Configurable Single-Instance Process Guard (`Application.instance.ensureSingleInstance`)**:
  - Supports both `InstanceMode.singleInstance` (default) and `InstanceMode.multiInstance`.
  - **Windows**: Uses a session-scoped Named Mutex (`CreateMutexW` + `WaitForSingleObject(0)`), delegates Foreground Lock via `AllowSetForegroundWindow`, and forwards CLI arguments & working directory (`SecondInstancePayload`) via `WM_COPYDATA`.
  - **Linux & macOS**: Uses a user-scoped Unix Domain Socket under the 104-byte BSD/macOS path limit with automatic `SIGKILL` stale-socket recovery.
- **Close-to-Tray Window Resolution & Foreground Restore (`mainWindow`)**:
  - Resolves hidden (`SW_HIDE` / `orderOut:` / `gtk_widget_hide`) primary windows reliably across all 3 desktop OSes and restores foreground focus.
- **Multi-Monitor Work Areas (`DisplayManager`)**: Queries physical monitor `bounds`, taskbar/dock-safe `workArea`, and DPI `scaleFactor` normalized to a top-left desktop coordinate origin.
- **Optional Non-Fatal Diagnostics (`NativeCoreDiagnostics.onError`)**: Zero-overhead in production (`null` by default), with full operation context & stack traces when enabled during development.

## Installation

```yaml
dependencies:
  native_core: ^1.0.0
```

## Quick Start

```dart
import 'package:flutter/widgets.dart';
import 'package:native_core/native_core.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final isPrimary = await Application.instance.ensureSingleInstance(
    appId: 'com.example.desktop_workspace',
    mode: args.contains('--multi-instance')
        ? InstanceMode.multiInstance
        : InstanceMode.singleInstance,
    arguments: args,
    onSecondInstance: (payload) {
      // Handle forwarded arguments from a secondary launch.
    },
  );
  if (!isPrimary) return;

  final window = mainWindow;
  if (window != null) {
    if (!hideLinuxNativeTitleBar(window)) {
      window.titleBarStyle = TitleBarStyle.hidden;
    }
    window
      ..minimumSize = const NativeSize(640, 420)
      ..title = 'Desktop Workspace'
      ..center()
      ..show()
      ..focus();
  }

  runApp(const SizedBox.shrink());
}
```

## License

Apache License 2.0 — Copyright 2026 Infradise Inc. See [LICENSE](LICENSE).
