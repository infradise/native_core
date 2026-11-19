import 'dart:ffi' as ffi;

import '../display_manager.dart';
import '../models.dart';

/// Callback sink through which an OS [WindowPlatformAdapter] notifies its
/// owning `Window` facade of asynchronous native OS events.
abstract interface class WindowAdapterEventSink {
  /// Dispatches a cancellable close request and returns `true` when closing is
  /// allowed to proceed (`false` when cancelled by a listener).
  bool dispatchCloseRequested();

  /// Notifies listeners that the native window moved to [position].
  void notifyNativeMoved(NativeOffset position);
}

/// Strategy contract implemented by each desktop OS window backend (`GTK3`,
/// `AppKit`, `Win32`) as well as `InMemoryWindowAdapter` for headless tests.
abstract interface class WindowPlatformAdapter {
  /// Raw native window pointer (`GtkWindow*`, `NSWindow*`, `HWND`), or
  /// `nullptr` for in-memory test adapters.
  ffi.Pointer<ffi.Void> get nativeHandle;

  /// Whether this adapter wraps a live OS window rather than an in-memory fake.
  bool get isNative;

  /// Attaches OS-level hooks or delegates and connects [sink] for callbacks.
  void attach(WindowAdapterEventSink sink);

  /// Current [TitleBarStyle].
  TitleBarStyle get titleBarStyle;
  set titleBarStyle(TitleBarStyle style);

  /// Whether native traffic-light / caption buttons are visible.
  bool get isWindowControlButtonsVisible;
  set isWindowControlButtonsVisible(bool visible);

  /// Current window background color.
  NativeColor get backgroundColor;
  set backgroundColor(NativeColor color);

  /// Whether the window is currently in fullscreen mode.
  bool get isFullScreen;
  set isFullScreen(bool value);

  /// Whether the window is currently maximized (zoomed).
  bool get isMaximized;

  /// Whether the window is currently minimized (iconified / miniaturized).
  bool get isMinimized;

  /// Whether the window is currently visible on screen (or queued for initial
  /// first-frame presentation).
  bool get isVisible;

  /// Whether the window currently owns foreground input focus.
  bool get isFocused;

  /// Minimum user-resizable window dimensions.
  NativeSize get minimumSize;
  set minimumSize(NativeSize size);

  /// Whether the window appears in the desktop taskbar / dock window list.
  bool get isVisibleInTaskbar;
  set isVisibleInTaskbar(bool visible);

  /// Window title text.
  String get title;
  set title(String value);

  /// Outer window rectangle in top-left desktop coordinates.
  NativeRect get bounds;
  set bounds(NativeRect rect);

  /// Resizes the window to [size], preserving its current top-left origin.
  void setSize(NativeSize size, {required bool animate});

  /// Maximizes the window to fill the monitor's usable work area.
  void maximize();

  /// Restores a maximized window back to its normal frame.
  void unmaximize();

  /// Minimizes (iconifies) the window.
  void minimize();

  /// Restores a minimized window without clobbering maximized state on OSes
  /// that track them independently.
  void restore();

  /// Makes the window visible and brings it to the foreground.
  void show();

  /// Hides the window without destroying its native handle (e.g. Close-to-Tray).
  void hide();

  /// Brings the window to the foreground and assigns keyboard focus.
  void focus();

  /// Destroys the underlying native OS window after close confirmation passes.
  void destroyNativeWindow();

  /// Begins an interactive OS window move drag gesture.
  void startDragging();

  /// Displays the native OS window system menu at [position], if supported.
  bool showSystemMenu(NativeOffset position);

  /// Detaches native hooks, signal handlers, delegates, and GDI resources.
  void dispose();
}

/// Strategy contract implemented by each desktop OS display query backend.
abstract interface class DisplayPlatformAdapter {
  /// Returns all connected displays with top-left normalized `bounds` and
  /// `workArea` rectangles.
  List<Display> getAll();
}
