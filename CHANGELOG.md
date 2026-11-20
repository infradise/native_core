## 1.0.1

OS-isolated window lifecycle, macOS Dock/close-button responsiveness, and Linux Wayland presentation & GDK3 pointer event fixes (with zero modifications to the Windows adapter).

### macOS (`platform/macos/`)
* **Immediate Close-to-Tray Response on Traffic-Light `[X]` Click**: Wake Flutter's macOS `CFRunLoop` / Dart microtask queue (`Timer.run` + `ensureVisualUpdate` / `scheduleFrame`) immediately inside `NativeCoreWindowDelegate.windowShouldClose:` when a close request is cancelled, so hiding the window no longer waits for the pointer to leave AppKit's red close button.
* **Automatic Dock Running Indicator Policy (`Regular` ↔ `Accessory`)**: When `MacOSWindowAdapter.hide()` hides the last visible app window while an active `NSStatusItem` (`NSStatusBarWindow` with `isVisible == true`) is present, automatically switch `NSApplication` to `Accessory (1)` so the Dock dot disappears while the menu bar icon stays alive; restore `Regular (0)` before activation on `show()`, `focus()`, or native reopen (`NSWindowDidBecomeKeyNotification`).
* **Clean Dock Quit / `Cmd+Q` Termination**: Stop forwarding `WidgetsBindingObserver.didRequestAppExit` to `WindowCloseRequestedEvent` on macOS and Linux (preserving Windows `WM_CLOSE` forwarding intact), and automatically release single-instance Unix sockets via `NSApplicationWillTerminateNotification` (`MacOSAppLifecycleObserver`) and `Application.quit()`.

### Linux (`platform/linux/`)
* **Wayland Unmapped Presentation & Mutter `"<App>" is ready` Fix**: Remove raw `gdk_window_show` and `gdk_window_focus` calls from `LinuxWindowAdapter._presentWindow`, and resolve X11 vs Wayland presentation via `resolveLinuxPresentAction` so unmapped Wayland startup/restore uses `gtk_window_deiconify` + `gtk_widget_show` without firing premature `gtk_window_present_with_time(0)`.
* **GTK3 Pre-Map Geometry, Native Centering, Maximized State, and Close Wakeup**: Apply `gtk_window_set_default_size` + `gdk_window_resize` before map in `setSize()` / `bounds =`, delegate `Window.center()` to `gtk_window_set_position(GTK_WIN_POS_CENTER)`, check `GDK_WINDOW_STATE_MAXIMIZED` alongside `gtk_window_is_maximized`, and wake Flutter's event loop when `delete-event` cancels close.
* **Synthesized `GDK_BUTTON_RELEASE` Pointer Device Binding**: Bind `gdk_event_set_device` and `gdk_event_get_device` from `libgdk-3.so.0` and attach the default `GdkSeat` pointer device inside `releaseLinuxMouseButtonAfterGrab` before dispatching `gtk_widget_event`, eliminating `Gdk-CRITICAL: gdk_device_get_axis: assertion 'GDK_IS_DEVICE (device)' failed` warnings after interactive caption-bar window dragging on Wayland and X11.

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
