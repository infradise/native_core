import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import 'diagnostics.dart';
import 'display_manager.dart';
import 'models.dart';
import 'platform/in_memory_window_adapter.dart';
import 'platform/linux/linux_window_adapter.dart';
import 'platform/macos/macos_window_adapter.dart';
import 'platform/window_adapter.dart';
import 'platform/windows/windows_window_adapter.dart';
import 'platform/windows/windows_window_finder.dart';

/// Pure policy deciding whether Flutter's [WidgetsBindingObserver.didRequestAppExit]
/// should be forwarded to [Window.dispatchCloseRequested].
///
/// * **Windows**: `true` — `Alt+F4` and taskbar "Close window" deliver
///   `WM_CLOSE` through Flutter's `didRequestAppExit`.
/// * **macOS**: `false` — window close buttons (`[X]` / `Cmd+W`) are already
///   intercepted natively by `NSWindowDelegate.windowShouldClose:`, whereas
///   `didRequestAppExit` signals an explicit OS-level application quit (Dock
///   Quit / `Cmd+Q`) that must be allowed to terminate cleanly.
/// * **Linux**: `false` — window close buttons and `Alt+F4` are intercepted
///   natively by GTK's `delete-event` signal, whereas `didRequestAppExit`
///   signals application termination.
bool shouldForwardAppExitToWindowClose({
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
}) {
  if (isMacOS || isLinux) return false;
  return isWindows;
}

/// Manages active desktop [Window] instances for the current process.
class WindowManager {
  WindowManager._();

  /// Process-wide singleton [WindowManager].
  static final WindowManager instance = WindowManager._();

  final Map<int, Window> _windowsById = <int, Window>{};
  final Map<int, Window> _windowsByAddress = <int, Window>{};

  /// Returns the registered [Window] with [id], or `null` if not found.
  Window? get(int id) => _windowsById[id];

  /// Resolves the current process's primary native desktop [Window], or `null`
  /// in headless test environments where no native window exists.
  Window? getCurrent() {
    final handle = _resolveCurrentNativeWindowHandle();
    if (handle == ffi.nullptr) return null;
    return _getOrWrap(handle);
  }

  Window _getOrWrap(ffi.Pointer<ffi.Void> handle) {
    final existing = _windowsByAddress[handle.address];
    if (existing != null) return existing;
    final created = Window._(_createPlatformAdapter(handle));
    _windowsById[created.id] = created;
    if (handle != ffi.nullptr) {
      _windowsByAddress[handle.address] = created;
    }
    return created;
  }

  void _unregister(Window window) {
    _windowsById.remove(window.id);
    if (window.nativeHandle != ffi.nullptr) {
      _windowsByAddress.remove(window.nativeHandle.address);
    }
  }

  WindowPlatformAdapter _createPlatformAdapter(ffi.Pointer<ffi.Void> handle) {
    if (handle == ffi.nullptr) {
      return InMemoryWindowAdapter();
    }
    if (Platform.isLinux) {
      return LinuxWindowAdapter(handle);
    }
    if (Platform.isWindows) {
      return WindowsWindowAdapter(handle);
    }
    if (Platform.isMacOS) {
      return MacOSWindowAdapter(handle);
    }
    return InMemoryWindowAdapter();
  }

  ffi.Pointer<ffi.Void> _resolveCurrentNativeWindowHandle() {
    if (Platform.isLinux) {
      return resolveLinuxMainWindowHandle(
        isPreviouslyRegistered: _windowsByAddress.containsKey,
      );
    }
    if (Platform.isWindows) {
      return findCurrentProcessFlutterWindowHandle() ?? ffi.nullptr;
    }
    if (Platform.isMacOS) {
      return resolveMacOSPrimaryWindowHandle();
    }
    return ffi.nullptr;
  }
}

/// Zero-dependency FFI facade around a native OS desktop window (`GtkWindow*`,
/// `HWND`, or `NSWindow*`).
class Window with WidgetsBindingObserver implements WindowAdapterEventSink {
  Window._(this._adapter) : id = _nextWindowId++ {
    _adapter.attach(this);
    _attachLifecycleObserver();
  }

  Window._withAdapter({
    required this.id,
    required WindowPlatformAdapter adapter,
  }) : _adapter = adapter {
    _adapter.attach(this);
    _isMaximizedState = _adapter.isMaximized;
    _isMinimizedState = _adapter.isMinimized;
    _boundsState = _adapter.bounds;
  }

  /// Wraps a raw native OS window handle (`GtkWindow*`, `HWND`, or
  /// `NSWindow*`).
  factory Window.createWithNativeWindow(ffi.Pointer<ffi.Void> handle) {
    return WindowManager.instance._getOrWrap(handle);
  }

  /// Creates an in-memory [Window] instance for unit and widget tests without
  /// touching OS FFI libraries.
  @visibleForTesting
  factory Window.fakeForTesting({
    int id = 1,
    bool isMaximized = false,
    bool isMinimized = false,
    bool isFullScreen = false,
    bool isVisible = true,
    bool isFocused = true,
    NativeRect bounds = const NativeRect(0, 0, 1280, 850),
  }) {
    return Window._withAdapter(
      id: id,
      adapter: InMemoryWindowAdapter(
        isMaximized: isMaximized,
        isMinimized: isMinimized,
        isFullScreen: isFullScreen,
        isVisible: isVisible,
        isFocused: isFocused,
        bounds: bounds,
      ),
    );
  }

  static int _nextWindowId = 1;
  static int _nextListenerId = 1;

  /// Monotonic runtime identifier for this [Window] wrapper.
  final int id;

  final WindowPlatformAdapter _adapter;

  /// Underlying native OS window pointer (`GtkWindow*`, `HWND`, `NSWindow*`),
  /// or `nullptr` for `Window.fakeForTesting`.
  ffi.Pointer<ffi.Void> get nativeHandle => _adapter.nativeHandle;

  /// Alias for [nativeHandle] preserved for platform helper interoperability.
  ffi.Pointer<ffi.Void> get nativeObject => _adapter.nativeHandle;

  final Map<ListenerId, void Function(WindowEvent)> _listeners =
      <ListenerId, void Function(WindowEvent)>{};

  bool _observerAttached = false;
  bool _isMaximizedState = false;
  bool _isMinimizedState = false;
  NativeRect _boundsState = const NativeRect(0, 0, 1280, 850);

  void _attachLifecycleObserver() {
    if (!_adapter.isNative) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
      _isMaximizedState = _adapter.isMaximized;
      _isMinimizedState = _adapter.isMinimized;
      _boundsState = _adapter.bounds;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'Window.attachLifecycleObserver',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool dispatchCloseRequested() {
    final request = EventRequest(cancellable: true);
    _emit(WindowCloseRequestedEvent(request));
    return !request.isCancelled;
  }

  @override
  void notifyNativeMoved(NativeOffset position) {
    if (position.dx != _boundsState.left || position.dy != _boundsState.top) {
      _boundsState = NativeRect(
        position.dx,
        position.dy,
        _boundsState.width,
        _boundsState.height,
      );
      _emit(WindowMovedEvent(position));
    }
  }

  @override
  void didChangeMetrics() {
    if (!_adapter.isNative) return;
    final nowMaximized = isMaximized;
    final nowMinimized = isMinimized;
    final nowBounds = bounds;

    if (nowMaximized != _isMaximizedState) {
      _isMaximizedState = nowMaximized;
      _emit(
        nowMaximized
            ? const WindowMaximizedEvent()
            : const WindowUnmaximizedEvent(),
      );
    }
    if (nowMinimized != _isMinimizedState) {
      _isMinimizedState = nowMinimized;
      _emit(
        nowMinimized
            ? const WindowMinimizedEvent()
            : const WindowRestoredEvent(),
      );
    }
    if (nowBounds.width != _boundsState.width ||
        nowBounds.height != _boundsState.height) {
      _boundsState = nowBounds;
      _emit(WindowResizedEvent(NativeSize(nowBounds.width, nowBounds.height)));
    } else if (nowBounds.left != _boundsState.left ||
        nowBounds.top != _boundsState.top) {
      _boundsState = nowBounds;
      _emit(WindowMovedEvent(NativeOffset(nowBounds.left, nowBounds.top)));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _emit(const WindowFocusedEvent());
    } else if (state == AppLifecycleState.inactive) {
      _emit(const WindowBlurredEvent());
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (shouldForwardAppExitToWindowClose(
      isWindows: Platform.isWindows,
      isMacOS: Platform.isMacOS,
      isLinux: Platform.isLinux,
    )) {
      return dispatchCloseRequested()
          ? AppExitResponse.exit
          : AppExitResponse.cancel;
    }
    return AppExitResponse.exit;
  }

  /// Registers a callback for window events and returns its [ListenerId].
  ListenerId addListener(void Function(WindowEvent event) listener) {
    final listenerId = ListenerId(_nextListenerId++);
    _listeners[listenerId] = listener;
    return listenerId;
  }

  /// Removes a previously registered window event listener.
  void removeListener(ListenerId listenerId) {
    _listeners.remove(listenerId);
  }

  /// Emits [event] to all registered listeners (exposed for unit/widget tests).
  @visibleForTesting
  void debugEmitEvent(WindowEvent event) => _emit(event);

  void _emit(WindowEvent event) {
    final snapshot = List<void Function(WindowEvent)>.of(_listeners.values);
    for (final listener in snapshot) {
      try {
        listener(event);
      } catch (error, stackTrace) {
        NativeCoreDiagnostics.report('Window.listener', error, stackTrace);
      }
    }
  }

  /// Visual style of the native window title bar (`normal` vs `hidden`).
  TitleBarStyle get titleBarStyle => _adapter.titleBarStyle;

  set titleBarStyle(TitleBarStyle style) {
    _adapter.titleBarStyle = style;
  }

  /// Whether native OS window control buttons (such as macOS traffic lights)
  /// are visible.
  bool get isWindowControlButtonsVisible =>
      _adapter.isWindowControlButtonsVisible;

  set isWindowControlButtonsVisible(bool value) {
    _adapter.isWindowControlButtonsVisible = value;
  }

  /// Background color applied behind the Flutter surface during initial startup
  /// and rapid resize passes.
  ///
  /// Applied natively via a Win32 GDI solid brush during `WM_ERASEBKGND` on
  /// Windows, and cached in memory on macOS and Linux.
  NativeColor get backgroundColor => _adapter.backgroundColor;

  set backgroundColor(NativeColor color) {
    _adapter.backgroundColor = color;
  }

  /// Whether the window is currently in fullscreen mode.
  bool get isFullScreen => _adapter.isFullScreen;

  set isFullScreen(bool value) {
    _adapter.isFullScreen = value;
  }

  /// Whether the window is currently maximized.
  bool get isMaximized => _adapter.isMaximized;

  /// Whether the window is currently minimized (iconified).
  bool get isMinimized => _adapter.isMinimized;

  /// Whether the window is currently visible on screen.
  bool get isVisible => _adapter.isVisible;

  /// Whether the window currently holds foreground keyboard focus.
  bool get isFocused => _adapter.isFocused;

  /// Minimum interactive resize dimensions of the window.
  NativeSize get minimumSize => _adapter.minimumSize;

  set minimumSize(NativeSize size) {
    _adapter.minimumSize = size;
  }

  /// Whether the window appears in the desktop taskbar.
  bool get isVisibleInTaskbar => _adapter.isVisibleInTaskbar;

  set isVisibleInTaskbar(bool visible) {
    _adapter.isVisibleInTaskbar = visible;
  }

  /// Window title text displayed in task switchers and native title bars.
  String get title => _adapter.title;

  set title(String value) {
    _adapter.title = value;
  }

  /// Outer window rectangle in top-left desktop coordinates.
  NativeRect get bounds => _adapter.bounds;

  set bounds(NativeRect rect) {
    _boundsState = rect;
    _adapter.bounds = rect;
  }

  /// Maximizes the window to fill the active monitor's usable work area.
  void maximize() {
    _isMaximizedState = true;
    _isMinimizedState = false;
    _adapter.maximize();
    _emit(const WindowMaximizedEvent());
  }

  /// Restores a maximized window back to its normal dimensions.
  void unmaximize() {
    _isMaximizedState = false;
    _adapter.unmaximize();
    _emit(const WindowUnmaximizedEvent());
    _emit(const WindowRestoredEvent());
  }

  /// Minimizes (iconifies) the window.
  void minimize() {
    _isMinimizedState = true;
    _adapter.minimize();
    _emit(const WindowMinimizedEvent());
  }

  /// Restores a minimized window.
  void restore() {
    _isMinimizedState = false;
    if (!_adapter.isNative) {
      _isMaximizedState = false;
    }
    _adapter.restore();
    _emit(const WindowRestoredEvent());
  }

  /// Shows the window and brings it to the foreground.
  void show() {
    _adapter.show();
  }

  /// Hides the window without destroying its native handle (e.g. Close-to-Tray).
  void hide() {
    _adapter.hide();
  }

  /// Brings the window to the foreground and assigns input focus.
  void focus() {
    _adapter.focus();
  }

  /// Requests closing the window; destroys the native window unless cancelled
  /// by a [WindowCloseRequestedEvent] listener.
  void close() {
    if (!dispatchCloseRequested()) return;
    _adapter.destroyNativeWindow();
  }

  /// Centers the window within the primary display's usable work area.
  void center() {
    if (_adapter case final LinuxWindowAdapter linux) {
      linux.centerNative();
      return;
    }
    final current = bounds;
    final displays = DisplayManager.instance.getAll();
    if (displays.isNotEmpty) {
      final work = displays.first.workArea;
      final cx = work.left + (work.width - current.width) / 2.0;
      final cy = work.top + (work.height - current.height) / 2.0;
      bounds = NativeRect(cx, cy, current.width, current.height);
    }
  }

  /// Resizes the window to [size], optionally animating on platforms that
  /// support frame animation.
  void setSize(NativeSize size, [bool animate = false]) {
    final current = bounds;
    _boundsState = NativeRect(
      current.left,
      current.top,
      size.width,
      size.height,
    );
    _adapter.setSize(size, animate: animate);
    _emit(WindowResizedEvent(size));
  }

  /// Initiates an interactive OS window drag gesture.
  void startDragging() {
    _adapter.startDragging();
  }

  /// Displays the native OS window system menu at [position].
  ///
  /// Supported natively on Windows (`GetSystemMenu` + `TrackPopupMenu`);
  /// returns `false` on macOS and Linux.
  bool showSystemMenu(NativeOffset position) {
    return _adapter.showSystemMenu(position);
  }

  /// Toggles window maximization on title bar double-click.
  void performTitleBarDoubleClick() {
    if (isMaximized) {
      unmaximize();
    } else {
      maximize();
    }
  }

  /// Releases native signal hooks, subclasses, delegates, and observers.
  void dispose() {
    if (_observerAttached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (error, stackTrace) {
        NativeCoreDiagnostics.report(
          'Window.removeLifecycleObserver',
          error,
          stackTrace,
        );
      }
      _observerAttached = false;
    }
    _adapter.dispose();
    _listeners.clear();
    WindowManager.instance._unregister(this);
  }
}
