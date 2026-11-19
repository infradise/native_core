import 'dart:ffi' as ffi;

import '../../diagnostics.dart';
import '../../ffi/native_memory.dart';
import '../../models.dart';
import '../window_adapter.dart';
import 'linux_gtk_bindings.dart';

/// Pure, testable selector for resolving the primary Linux `GtkWindow` from
/// `gtk_window_list_toplevels()` without accidentally picking a prepended
/// `GTK_WINDOW_POPUP` (`GtkTooltip`, `GtkMenu`, or IME popup).
T? selectPrimaryLinuxToplevel<T extends Object>({
  required List<T> candidates,
  required bool Function(T candidate) isToplevelType,
  required bool Function(T candidate) isAlive,
  required bool Function(T candidate) isRealized,
  required bool Function(T candidate) isVisible,
  required bool Function(T candidate) isActive,
  required bool Function(T candidate) isPreviouslyRegistered,
}) {
  T? firstVisible;
  T? registeredHidden;
  T? firstHidden;
  T? firstUnrealized;

  for (final candidate in candidates) {
    if (!isToplevelType(candidate) || !isAlive(candidate)) continue;
    if (!isRealized(candidate)) {
      firstUnrealized ??= candidate;
      continue;
    }
    if (isVisible(candidate)) {
      if (isActive(candidate)) return candidate;
      firstVisible ??= candidate;
    } else {
      if (registeredHidden == null && isPreviouslyRegistered(candidate)) {
        registeredHidden = candidate;
      }
      firstHidden ??= candidate;
    }
  }

  return firstVisible ?? registeredHidden ?? firstHidden ?? firstUnrealized;
}

/// Deterministic GObject signal teardown tracker enforcing that connected
/// signal handlers are always disconnected via `g_signal_handler_disconnect`
/// BEFORE closing `NativeCallable` trampolines while a `GtkWindow` is alive.
class LinuxSignalLifecycle {
  /// Creates a [LinuxSignalLifecycle] tracker.
  LinuxSignalLifecycle({
    required this.disconnectSignal,
    required this.closeCallables,
  });

  /// Disconnects a live GObject signal handler ID from the widget.
  final void Function(int handlerId) disconnectSignal;

  /// Closes the Dart `NativeCallable` trampolines after signal disconnection.
  final void Function() closeCallables;

  int _deleteEventId = 0;
  int _destroyEventId = 0;
  bool _widgetDestroyed = false;
  bool _disposed = false;

  /// Records the connected `delete-event` and `destroy` signal handler IDs.
  void recordConnected({
    required int deleteEventId,
    required int destroyEventId,
  }) {
    _deleteEventId = deleteEventId;
    _destroyEventId = destroyEventId;
  }

  /// Marks the `GtkWidget` as destroyed by GTK (`"destroy"` signal), releasing
  /// the `NativeCallable` trampolines without touching freed GObject memory.
  void handleWidgetDestroyed() {
    if (_disposed) return;
    _widgetDestroyed = true;
    _deleteEventId = 0;
    _destroyEventId = 0;
    _disposed = true;
    closeCallables();
  }

  /// Disconnects any active GObject signals (if the widget is still alive)
  /// strictly BEFORE closing the `NativeCallable` trampolines.
  void dispose({required bool isWidgetAlive}) {
    if (_disposed) return;
    _disposed = true;
    if (!_widgetDestroyed && isWidgetAlive) {
      if (_deleteEventId > 0) {
        disconnectSignal(_deleteEventId);
      }
      if (_destroyEventId > 0) {
        disconnectSignal(_destroyEventId);
      }
    }
    _deleteEventId = 0;
    _destroyEventId = 0;
    closeCallables();
  }
}

/// Resolves the current process's primary `GtkWindow*` on Linux, or `nullptr`
/// when running headless (`gdk_display_get_default() == nullptr`).
ffi.Pointer<ffi.Void> resolveLinuxMainWindowHandle({
  required bool Function(int address) isPreviouslyRegistered,
}) {
  final gtk = LinuxGtkBindings.instance;
  if (gtk == null) return ffi.nullptr;
  try {
    if (gtk.gdkDisplayGetDefault() == ffi.nullptr) {
      return ffi.nullptr;
    }
    final toplevels = gtk.gtkWindowListToplevels();
    if (toplevels == ffi.nullptr) return ffi.nullptr;
    try {
      final candidates = <ffi.Pointer<ffi.Void>>[];
      var cursor = toplevels;
      while (cursor != ffi.nullptr) {
        final candidate = cursor.ref.data;
        if (candidate != ffi.nullptr) {
          candidates.add(candidate);
        }
        cursor = cursor.ref.next;
      }
      final selected = selectPrimaryLinuxToplevel<ffi.Pointer<ffi.Void>>(
        candidates: candidates,
        isToplevelType:
            (w) => gtk.gtkWindowGetWindowType(w) == kGtkWindowToplevel,
        isAlive: (w) => gtk.gtkWidgetInDestruction(w) == 0,
        isRealized: (w) => gtk.gtkWidgetGetRealized(w) != 0,
        isVisible: (w) => gtk.gtkWidgetGetVisible(w) != 0,
        isActive: (w) => gtk.gtkWindowIsActive(w) != 0,
        isPreviouslyRegistered: (w) => isPreviouslyRegistered(w.address),
      );
      return selected ?? ffi.nullptr;
    } finally {
      gtk.gListFree(toplevels);
    }
  } catch (error, stackTrace) {
    NativeCoreDiagnostics.report(
      'resolveLinuxMainWindowHandle',
      error,
      stackTrace,
    );
    return ffi.nullptr;
  }
}

/// Quits the default `GApplication` event loop on Linux if one is active.
void quitLinuxApplication() {
  final gtk = LinuxGtkBindings.instance;
  if (gtk == null) return;
  try {
    final app = gtk.gApplicationGetDefault();
    if (app != ffi.nullptr) {
      gtk.gApplicationQuit(app);
    }
  } catch (error, stackTrace) {
    NativeCoreDiagnostics.report('quitLinuxApplication', error, stackTrace);
  }
}

/// GTK3 / GDK3 implementation of [WindowPlatformAdapter] for Linux X11 and
/// Wayland sessions.
class LinuxWindowAdapter implements WindowPlatformAdapter {
  /// Creates a [LinuxWindowAdapter] wrapping [nativeHandle] (`GtkWindow*`).
  LinuxWindowAdapter(this.nativeHandle);

  static final Map<int, LinuxWindowAdapter> _activeByAddress =
      <int, LinuxWindowAdapter>{};

  @override
  final ffi.Pointer<ffi.Void> nativeHandle;

  @override
  bool get isNative => nativeHandle != ffi.nullptr;

  WindowAdapterEventSink? _sink;
  LinuxSignalLifecycle? _signalLifecycle;
  ffi.NativeCallable<
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
    )
  >?
  _deleteEventCallable;
  ffi.NativeCallable<
    ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)
  >?
  _destroyCallable;

  TitleBarStyle _titleBarStyle = TitleBarStyle.normal;
  bool _isWindowControlButtonsVisible = true;
  NativeColor _backgroundColor = const NativeColor(0x00000000);
  bool _isFullScreen = false;
  NativeSize _minimumSize = const NativeSize(500, 300);
  bool _isVisibleInTaskbar = true;
  String _title = '';
  NativeRect _fallbackBounds = const NativeRect(0, 0, 1280, 850);

  @override
  void attach(WindowAdapterEventSink sink) {
    _sink = sink;
    if (!isNative) return;
    _activeByAddress[nativeHandle.address] = this;

    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;

    var deleteId = 0;
    var destroyId = 0;
    try {
      _deleteEventCallable = ffi.NativeCallable<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>,
        )
      >.isolateLocal(_onDeleteEvent, exceptionalReturn: 0);
      _destroyCallable = ffi.NativeCallable<
        ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)
      >.isolateLocal(_onDestroyEvent);

      NativeMemory.withUtf8CString('delete-event', (name) {
        deleteId = gtk.gSignalConnectData(
          nativeHandle,
          name,
          _deleteEventCallable!.nativeFunction.cast(),
          ffi.nullptr,
          ffi.nullptr,
          0,
        );
      });
      NativeMemory.withUtf8CString('destroy', (name) {
        destroyId = gtk.gSignalConnectData(
          nativeHandle,
          name,
          _destroyCallable!.nativeFunction.cast(),
          ffi.nullptr,
          ffi.nullptr,
          0,
        );
      });

      _signalLifecycle = LinuxSignalLifecycle(
        disconnectSignal: (handlerId) {
          if (gtk.gSignalHandlerIsConnected(nativeHandle, handlerId) != 0) {
            gtk.gSignalHandlerDisconnect(nativeHandle, handlerId);
          }
        },
        closeCallables: () {
          _deleteEventCallable?.close();
          _deleteEventCallable = null;
          _destroyCallable?.close();
          _destroyCallable = null;
        },
      )..recordConnected(deleteEventId: deleteId, destroyEventId: destroyId);
    } catch (error, stackTrace) {
      if (deleteId > 0 &&
          gtk.gSignalHandlerIsConnected(nativeHandle, deleteId) != 0) {
        gtk.gSignalHandlerDisconnect(nativeHandle, deleteId);
      }
      if (destroyId > 0 &&
          gtk.gSignalHandlerIsConnected(nativeHandle, destroyId) != 0) {
        gtk.gSignalHandlerDisconnect(nativeHandle, destroyId);
      }
      _deleteEventCallable?.close();
      _deleteEventCallable = null;
      _destroyCallable?.close();
      _destroyCallable = null;
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.attach',
        error,
        stackTrace,
      );
    }
  }

  static int _onDeleteEvent(
    ffi.Pointer<ffi.Void> widget,
    ffi.Pointer<ffi.Void> event,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final adapter = _activeByAddress[widget.address];
    final sink = adapter?._sink;
    if (sink == null) return 0;
    final allowClose = sink.dispatchCloseRequested();
    return allowClose ? 0 : 1;
  }

  static void _onDestroyEvent(
    ffi.Pointer<ffi.Void> widget,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final adapter = _activeByAddress.remove(widget.address);
    adapter?._signalLifecycle?.handleWidgetDestroyed();
  }

  @override
  TitleBarStyle get titleBarStyle => _titleBarStyle;

  @override
  set titleBarStyle(TitleBarStyle style) {
    _titleBarStyle = style;
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      final titlebar = gtk.gtkWindowGetTitlebar(nativeHandle);
      if (style == TitleBarStyle.hidden) {
        if (titlebar != ffi.nullptr) {
          gtk.gtkWidgetSetVisible(titlebar, 0);
        } else {
          gtk.gtkWindowSetDecorated(nativeHandle, 0);
        }
      } else {
        if (titlebar != ffi.nullptr) {
          gtk.gtkWidgetSetVisible(titlebar, 1);
        } else {
          gtk.gtkWindowSetDecorated(nativeHandle, 1);
        }
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.titleBarStyle',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool get isWindowControlButtonsVisible => _isWindowControlButtonsVisible;

  @override
  set isWindowControlButtonsVisible(bool visible) {
    _isWindowControlButtonsVisible = visible;
  }

  @override
  NativeColor get backgroundColor => _backgroundColor;

  @override
  set backgroundColor(NativeColor color) {
    _backgroundColor = color;
  }

  @override
  bool get isFullScreen => _isFullScreen;

  @override
  set isFullScreen(bool value) {
    _isFullScreen = value;
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      if (value) {
        gtk.gtkWindowFullscreen(nativeHandle);
      } else {
        gtk.gtkWindowUnfullscreen(nativeHandle);
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.isFullScreen',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool get isMaximized {
    if (!isNative) return false;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return false;
    try {
      return gtk.gtkWindowIsMaximized(nativeHandle) != 0;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.isMaximized',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  bool get isMinimized {
    if (!isNative) return false;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return false;
    try {
      final gdkWin = gtk.gtkWidgetGetWindow(nativeHandle);
      if (gdkWin != ffi.nullptr) {
        return (gtk.gdkWindowGetState(gdkWin) & kGdkWindowStateIconified) != 0;
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.isMinimized',
        error,
        stackTrace,
      );
    }
    return false;
  }

  @override
  bool get isVisible {
    if (!isNative) return false;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return false;
    try {
      return gtk.gtkWidgetGetVisible(nativeHandle) != 0;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.isVisible',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  bool get isFocused {
    if (!isNative) return false;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return false;
    try {
      return gtk.gtkWindowIsActive(nativeHandle) != 0;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.isFocused',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  NativeSize get minimumSize => _minimumSize;

  @override
  set minimumSize(NativeSize size) {
    _minimumSize = size;
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      gtk.gtkWidgetSetSizeRequest(
        nativeHandle,
        size.width.round(),
        size.height.round(),
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.minimumSize',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool get isVisibleInTaskbar => _isVisibleInTaskbar;

  @override
  set isVisibleInTaskbar(bool visible) {
    _isVisibleInTaskbar = visible;
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      gtk.gtkWindowSetSkipTaskbarHint(nativeHandle, visible ? 0 : 1);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.isVisibleInTaskbar',
        error,
        stackTrace,
      );
    }
  }

  @override
  String get title => _title;

  @override
  set title(String value) {
    _title = value;
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      NativeMemory.withUtf8CString(
        value,
        (cstr) => gtk.gtkWindowSetTitle(nativeHandle, cstr),
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.title',
        error,
        stackTrace,
      );
    }
  }

  @override
  NativeRect get bounds {
    if (!isNative) return _fallbackBounds;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return _fallbackBounds;
    try {
      final ints = gtk.scratchInts;
      gtk.gtkWindowGetPosition(nativeHandle, ints, ints + 1);
      gtk.gtkWindowGetSize(nativeHandle, ints + 2, ints + 3);
      return _fallbackBounds = NativeRect(
        ints[0].toDouble(),
        ints[1].toDouble(),
        ints[2].toDouble(),
        ints[3].toDouble(),
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.bounds',
        error,
        stackTrace,
      );
      return _fallbackBounds;
    }
  }

  @override
  set bounds(NativeRect rect) {
    _fallbackBounds = rect;
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      gtk.gtkWindowMove(nativeHandle, rect.left.round(), rect.top.round());
      gtk.gtkWindowResize(
        nativeHandle,
        rect.width.round(),
        rect.height.round(),
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.setBounds',
        error,
        stackTrace,
      );
    }
  }

  @override
  void setSize(NativeSize size, {required bool animate}) {
    final current = bounds;
    _fallbackBounds = NativeRect(
      current.left,
      current.top,
      size.width,
      size.height,
    );
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      gtk.gtkWindowResize(
        nativeHandle,
        size.width.round(),
        size.height.round(),
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.setSize',
        error,
        stackTrace,
      );
    }
  }

  @override
  void maximize() {
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      gtk.gtkWindowMaximize(nativeHandle);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.maximize',
        error,
        stackTrace,
      );
    }
  }

  @override
  void unmaximize() {
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      gtk.gtkWindowUnmaximize(nativeHandle);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.unmaximize',
        error,
        stackTrace,
      );
    }
  }

  @override
  void minimize() {
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      gtk.gtkWindowIconify(nativeHandle);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.minimize',
        error,
        stackTrace,
      );
    }
  }

  @override
  void restore() {
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      gtk.gtkWindowDeiconify(nativeHandle);
      _presentWindow(gtk);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.restore',
        error,
        stackTrace,
      );
    }
  }

  @override
  void show() {
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      _presentWindow(gtk);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.show',
        error,
        stackTrace,
      );
    }
  }

  @override
  void hide() {
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      gtk.gtkWidgetHide(nativeHandle);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.hide',
        error,
        stackTrace,
      );
    }
  }

  @override
  void focus() {
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      _presentWindow(gtk);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.focus',
        error,
        stackTrace,
      );
    }
  }

  @override
  void destroyNativeWindow() {
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      gtk.gtkWidgetDestroy(nativeHandle);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.destroyNativeWindow',
        error,
        stackTrace,
      );
    }
  }

  @override
  void startDragging() {
    if (!isNative) return;
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return;
    try {
      final gdkWin = gtk.gtkWidgetGetWindow(nativeHandle);
      final display = gtk.gdkDisplayGetDefault();
      if (gdkWin == ffi.nullptr || display == ffi.nullptr) return;
      final seat = gtk.gdkDisplayGetDefaultSeat(display);
      if (seat == ffi.nullptr) return;
      final pointer = gtk.gdkSeatGetPointer(seat);
      if (pointer == ffi.nullptr) return;

      final coords = gtk.scratchInts;
      gtk.gdkDeviceGetPosition(pointer, ffi.nullptr, coords, coords + 1);
      gtk.gtkWindowBeginMoveDrag(nativeHandle, 1, coords[0], coords[1], 0);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxWindowAdapter.startDragging',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool showSystemMenu(NativeOffset position) => false;

  void _presentWindow(LinuxGtkBindings gtk) {
    gtk.gtkWidgetShow(nativeHandle);
    gtk.gtkWindowDeiconify(nativeHandle);

    final gdkWin = gtk.gtkWidgetGetWindow(nativeHandle);
    var timestamp = gtk.gtkGetCurrentEventTime();
    if (timestamp == 0 && gdkWin != ffi.nullptr) {
      // When triggered from a D-Bus StatusNotifierItem menu click, there is no
      // active GDK event (`timestamp == 0`). On X11/XWayland, fetch a fresh X
      // server timestamp so Mutter/KWin focus-stealing prevention does not
      // reject `_NET_ACTIVE_WINDOW` due to a stale pre-hide user timestamp.
      final x11GetType = gtk.gdkX11WindowGetType;
      final x11ServerTime = gtk.gdkX11GetServerTime;
      if (x11GetType != null && x11ServerTime != null) {
        try {
          if (gtk.gTypeCheckInstanceIsA(gdkWin, x11GetType()) != 0) {
            timestamp = x11ServerTime(gdkWin);
          }
        } catch (error, stackTrace) {
          NativeCoreDiagnostics.report(
            'LinuxWindowAdapter.x11Timestamp',
            error,
            stackTrace,
          );
        }
      }
    }

    gtk.gtkWindowPresentWithTime(nativeHandle, timestamp);
    if (gdkWin != ffi.nullptr) {
      gtk.gdkWindowShow(gdkWin);
      gtk.gdkWindowFocus(gdkWin, timestamp);
    }
  }

  @override
  void dispose() {
    _activeByAddress.remove(nativeHandle.address);
    final gtk = LinuxGtkBindings.instance;
    var alive = false;
    if (isNative && gtk != null) {
      try {
        alive = gtk.gtkWidgetInDestruction(nativeHandle) == 0;
      } catch (_) {
        alive = false;
      }
    }
    final lifecycle = _signalLifecycle;
    _signalLifecycle = null;
    if (lifecycle != null) {
      lifecycle.dispose(isWidgetAlive: alive);
    } else {
      _deleteEventCallable?.close();
      _deleteEventCallable = null;
      _destroyCallable?.close();
      _destroyCallable = null;
    }
    _sink = null;
  }
}
