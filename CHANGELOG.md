## 1.0.0

Initial stable release of **`native_core`** — a unified, zero-dependency desktop window, display, and single-instance application lifecycle package for Flutter across **Linux** (`GTK3` / `GDK3` on Wayland & X11), **macOS** (`AppKit` 13.0+), and **Windows** (`Win32`).

### Architecture & Platform Highlights
* **Zero External Dependencies**: Depends solely on the Flutter SDK (`flutter`), isolating each desktop OS inside dedicated `WindowPlatformAdapter` and `DisplayPlatformAdapter` implementations (`platform/linux/`, `platform/macos/`, `platform/windows/`) with one-time cached FFI symbol and Objective-C selector tables plus optional `NativeCoreDiagnostics.onError` reporting.
* **Configurable Single-Instance Coordination (`Application.instance.ensureSingleInstance`)**:
  * Supports `InstanceMode.singleInstance` (default) and `InstanceMode.multiInstance`, forwarding CLI arguments and working directory via `SecondInstancePayload`.
  * **Windows**: Uses a session-scoped Named Mutex (`CreateMutexW` + `WaitForSingleObject(0)` for atomic crash recovery via `WAIT_ABANDONED`), `AllowSetForegroundWindow` foreground-lock handoff, and a Hot Restart-safe `WM_COPYDATA` IPC host window.
  * **Linux & macOS**: Uses a user-scoped Unix Domain Socket constrained below the 104-byte `sockaddr_un.sun_path` limit with automatic `SIGKILL` stale-socket recovery and client inactivity timeout protection.
* **Linux (`libgtk-3.so.0`, `libgdk-3.so.0`, `libgobject-2.0.so.0`, `libgio-2.0.so.0`)**:
  * Filters `gtk_window_list_toplevels()` strictly for live `GTK_WINDOW_TOPLEVEL` (`0`) windows (`selectPrimaryLinuxToplevel`), skipping `GTK_WINDOW_POPUP` (`1`) tooltips and menus.
  * Tracks `delete-event` and `destroy` GObject signal handler IDs (`LinuxSignalLifecycle`), disconnecting active handlers via `g_signal_handler_disconnect` strictly before closing `NativeCallable` trampolines (including partial attach rollback).
  * Restores hidden/minimized windows via `gtk_widget_show` + `gtk_window_deiconify` + `gtk_window_present_with_time` (with X11 `gdk_x11_get_server_time` resolution), hides `GtkHeaderBar` directly (`hideLinuxNativeTitleBar`), and synthesizes `GDK_BUTTON_RELEASE` after native grabs.
* **macOS (`/usr/lib/libobjc.A.dylib`, `AppKit`, `CoreGraphics`)**:
  * Universal Binary (`arm64` / `x86_64` `objc_msgSend_stret`) window and `NSScreen` geometry with Cocoa bottom-left to desktop top-left coordinate normalization.
  * Resolves hidden (`orderOut:`) primary windows via `NSApplication.windows` fallback, activates apps across macOS 13 Ventura through macOS 27+ via both `activate` and `activateIgnoringOtherApps:`, enables `NSWindowStyleMaskFullSizeContentView` (`1 << 15`), and intercepts `windowShouldClose:` / `windowDidMove:` with `class_replaceMethod` Hot Restart safety.
* **Windows (`user32.dll`, `comctl32.dll`, `dwmapi.dll`, `gdi32.dll`, `shcore.dll`, `kernel32.dll`)**:
  * Self-contained `SetWindowSubclass` custom frameless mode (`WM_NCCALCSIZE` maximized `rcWork` clamping, DWM shadow & rounded corners, 8-direction `WM_NCHITTEST` resize preserving Fitts's Law maximized top-right clicks, `WM_GETMINMAXINFO` `minimumSize`, `WM_ERASEBKGND` `WHITE_BRUSH` flash suppression without live DXGI resize strobe flicker, `WM_WINDOWPOSCHANGING` first-frame coordination with stock `flutter_window.cpp`, and pre-`DefSubclassProc` `WM_DESTROY` teardown).
  * Enumerates physical monitors with per-monitor work areas and DPI `scaleFactor` via `EnumDisplayMonitors` + `GetMonitorInfoW` + `GetDpiForMonitor` (with scoped `NativeCallable` teardown), and bypasses Foreground Lock on tray restore via `AttachThreadInput` and safe Z-order lift fallback.
