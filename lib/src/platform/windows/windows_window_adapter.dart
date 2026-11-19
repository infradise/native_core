import 'dart:ffi' as ffi;

import '../../diagnostics.dart';
import '../../ffi/native_memory.dart';
import '../../models.dart';
import '../window_adapter.dart';
import 'windows_frame_subclass.dart';
import 'windows_win32_bindings.dart';

/// Win32 (`HWND`) implementation of [WindowPlatformAdapter] for Windows 10 and
/// Windows 11.
class WindowsWindowAdapter implements WindowPlatformAdapter {
  /// Creates a [WindowsWindowAdapter] wrapping [nativeHandle] (`HWND`).
  WindowsWindowAdapter(this.nativeHandle) {
    _frameController = WindowsFrameController(
      hwnd: nativeHandle,
      onApplyDeferredMaximize: () => _showWindow(kSwShowMaximized),
      onApplyDeferredFocus: _focusNativeWindow,
    );
  }

  @override
  final ffi.Pointer<ffi.Void> nativeHandle;

  @override
  bool get isNative => nativeHandle != ffi.nullptr;

  late final WindowsFrameController _frameController;

  bool _isWindowControlButtonsVisible = true;
  NativeColor _backgroundColor = const NativeColor(0x00000000);
  bool _isFullScreen = false;
  int _preFullScreenStyle = 0;
  NativeRect? _preFullScreenBounds;
  NativeSize _minimumSize = const NativeSize(500, 300);
  bool _isVisibleInTaskbar = true;
  String _title = '';
  NativeRect _fallbackBounds = const NativeRect(0, 0, 1280, 850);

  @override
  void attach(WindowAdapterEventSink sink) {
    if (!isNative) return;
    _frameController.attach();
  }

  @override
  TitleBarStyle get titleBarStyle => _frameController.titleBarStyle;

  @override
  set titleBarStyle(TitleBarStyle style) {
    _frameController.applyTitleBarStyle(style);
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
    if (!isNative) return;
    _frameController.setBackgroundColor(color);
  }

  @override
  bool get isFullScreen => _isFullScreen;

  @override
  set isFullScreen(bool value) {
    if (_isFullScreen == value) return;
    _isFullScreen = value;
    _frameController.isFullScreen = value;
    if (!isNative) return;

    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return;
    try {
      if (value) {
        _preFullScreenStyle = win32.getWindowLongPtrW(nativeHandle, kGwlStyle);
        _preFullScreenBounds = bounds;
        win32.setWindowLongPtrW(
          nativeHandle,
          kGwlStyle,
          _preFullScreenStyle & ~kWsOverlappedWindow,
        );
        final monitor = win32.monitorFromWindow(
          nativeHandle,
          kMonitorDefaultToNearest,
        );
        if (monitor != ffi.nullptr) {
          final mi = win32.scratchMonitorInfo;
          mi.ref.cbSize = ffi.sizeOf<Win32MonitorInfo>();
          if (win32.getMonitorInfoW(monitor, mi) != 0) {
            final m = mi.ref.rcMonitor;
            win32.setWindowPos(
              nativeHandle,
              ffi.nullptr,
              m.left,
              m.top,
              m.right - m.left,
              m.bottom - m.top,
              kSwpFrameChanged | kSwpNoZOrder | kSwpNoActivate,
            );
          }
        }
      } else {
        if (_preFullScreenStyle != 0) {
          win32.setWindowLongPtrW(nativeHandle, kGwlStyle, _preFullScreenStyle);
        }
        final saved = _preFullScreenBounds;
        if (saved != null) {
          win32.setWindowPos(
            nativeHandle,
            ffi.nullptr,
            saved.left.round(),
            saved.top.round(),
            saved.width.round(),
            saved.height.round(),
            kSwpFrameChanged | kSwpNoZOrder | kSwpNoActivate,
          );
        } else {
          _frameController.applyTitleBarStyle(_frameController.titleBarStyle);
        }
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.isFullScreen',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool get isMaximized {
    if (!isNative) return false;
    if (_frameController.isDeferringInitialShow) {
      return _frameController.pendingMaximize;
    }
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return false;
    try {
      return win32.isZoomed(nativeHandle) != 0;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.isMaximized',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  bool get isMinimized {
    if (!isNative) return false;
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return false;
    try {
      return win32.isIconic(nativeHandle) != 0;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.isMinimized',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  bool get isVisible {
    if (!isNative) return false;
    if (_frameController.isDeferringInitialShow) {
      return _frameController.pendingShow;
    }
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return false;
    try {
      return win32.isWindowVisible(nativeHandle) != 0;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.isVisible',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  bool get isFocused {
    if (!isNative) return false;
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return false;
    try {
      return win32.getForegroundWindow().address == nativeHandle.address;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.isFocused',
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
    _frameController.minimumSize = size;
  }

  @override
  bool get isVisibleInTaskbar => _isVisibleInTaskbar;

  @override
  set isVisibleInTaskbar(bool visible) {
    _isVisibleInTaskbar = visible;
    if (!isNative) return;
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return;
    try {
      final exStyle = win32.getWindowLongPtrW(nativeHandle, kGwlExStyle);
      final targetExStyle =
          visible
              ? ((exStyle & ~kWsExToolWindow) | kWsExAppWindow)
              : ((exStyle & ~kWsExAppWindow) | kWsExToolWindow);
      if (targetExStyle != exStyle) {
        win32.setWindowLongPtrW(nativeHandle, kGwlExStyle, targetExStyle);
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.isVisibleInTaskbar',
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
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return;
    try {
      NativeMemory.withUtf16WString(
        value,
        (wstr) => win32.setWindowTextW(nativeHandle, wstr),
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.title',
        error,
        stackTrace,
      );
    }
  }

  @override
  NativeRect get bounds {
    if (!isNative) return _fallbackBounds;
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return _fallbackBounds;
    try {
      final rectPtr = win32.scratchRect;
      if (win32.getWindowRect(nativeHandle, rectPtr) != 0) {
        return _fallbackBounds = NativeRect(
          rectPtr.ref.left.toDouble(),
          rectPtr.ref.top.toDouble(),
          (rectPtr.ref.right - rectPtr.ref.left).toDouble(),
          (rectPtr.ref.bottom - rectPtr.ref.top).toDouble(),
        );
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.bounds',
        error,
        stackTrace,
      );
    }
    return _fallbackBounds;
  }

  @override
  set bounds(NativeRect rect) {
    _fallbackBounds = rect;
    if (!isNative) return;
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return;
    try {
      win32.setWindowPos(
        nativeHandle,
        ffi.nullptr,
        rect.left.round(),
        rect.top.round(),
        rect.width.round(),
        rect.height.round(),
        kSwpNoZOrder | kSwpNoActivate,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.setBounds',
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
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return;
    try {
      win32.setWindowPos(
        nativeHandle,
        ffi.nullptr,
        0,
        0,
        size.width.round(),
        size.height.round(),
        kSwpNoMove | kSwpNoZOrder | kSwpNoActivate,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.setSize',
        error,
        stackTrace,
      );
    }
  }

  @override
  void maximize() {
    if (!isNative) return;
    if (_frameController.recordMaximizeIfDeferred()) return;
    _showWindow(kSwShowMaximized);
  }

  @override
  void unmaximize() {
    if (!isNative) return;
    if (_frameController.recordUnmaximizeIfDeferred()) return;
    _showWindow(kSwRestore);
  }

  @override
  void minimize() {
    if (!isNative) return;
    _frameController.cancelDeferralForMinimize();
    _showWindow(kSwMinimize);
  }

  @override
  void restore() {
    if (!isNative) return;
    if (_frameController.isDeferringInitialShow) return;
    _showWindow(kSwRestore);
  }

  @override
  void show() {
    if (!isNative) return;
    if (_frameController.recordShowIfDeferred()) return;
    if (isMinimized) {
      _showWindow(kSwRestore);
    } else if (isMaximized) {
      _showWindow(kSwShowMaximized);
    } else {
      _showWindow(kSwShow);
    }
    _focusNativeWindow();
  }

  @override
  void hide() {
    if (!isNative) return;
    if (_frameController.recordHideIfDeferred()) return;
    _showWindow(kSwHide);
  }

  @override
  void focus() {
    if (!isNative) return;
    if (_frameController.recordFocusIfDeferred()) return;
    _focusNativeWindow();
  }

  @override
  void destroyNativeWindow() {
    if (!isNative) return;
    _frameController.detach();
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return;
    try {
      win32.destroyWindow(nativeHandle);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.destroyNativeWindow',
        error,
        stackTrace,
      );
    }
  }

  @override
  void startDragging() {
    if (!isNative) return;
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return;
    try {
      win32.releaseCapture();
      win32.sendMessageW(nativeHandle, kWmNcLButtonDown, kHtCaption, 0);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.startDragging',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool showSystemMenu(NativeOffset position) {
    if (!isNative) return false;
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return false;
    try {
      final hMenu = win32.getSystemMenu(nativeHandle, 0);
      if (hMenu == ffi.nullptr) return false;

      final pt = win32.scratchPoint;
      win32.getCursorPos(pt);
      final cmd = win32.trackPopupMenu(
        hMenu,
        kTpmReturnCmd | kTpmRightButton,
        pt.ref.x,
        pt.ref.y,
        0,
        nativeHandle,
        ffi.nullptr,
      );
      if (cmd != 0) {
        win32.postMessageW(nativeHandle, kWmSysCommand, cmd, 0);
      }
      return true;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.showSystemMenu',
        error,
        stackTrace,
      );
      return false;
    }
  }

  void _showWindow(int cmdShow) {
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null || !isNative) return;
    try {
      win32.showWindow(nativeHandle, cmdShow);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.showWindow',
        error,
        stackTrace,
      );
    }
  }

  void _focusNativeWindow() {
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null || !isNative) return;
    try {
      if (win32.isIconic(nativeHandle) != 0) {
        win32.showWindow(nativeHandle, kSwRestore);
      }

      if (win32.setForegroundWindow(nativeHandle) == 0 ||
          win32.getForegroundWindow().address != nativeHandle.address) {
        final foreground = win32.getForegroundWindow();
        final foregroundThread =
            foreground != ffi.nullptr
                ? win32.getWindowThreadProcessId(foreground, ffi.nullptr)
                : 0;
        final selfThread = win32.getCurrentThreadId();
        final attached =
            foregroundThread != 0 &&
            foregroundThread != selfThread &&
            win32.attachThreadInput(selfThread, foregroundThread, 1) != 0;

        win32.bringWindowToTop(nativeHandle);
        win32.setForegroundWindow(nativeHandle);
        if (attached) {
          win32.attachThreadInput(selfThread, foregroundThread, 0);
        }
      }

      // Z-order raise fallback when Windows 11 tray overflow flyout dismissal
      // leaves GetForegroundWindow() transiently null or UIPI blocks
      // AttachThreadInput: lift above normal windows without sticky TOPMOST.
      if (win32.getForegroundWindow().address != nativeHandle.address) {
        final wasTopMost =
            (win32.getWindowLongPtrW(nativeHandle, kGwlExStyle) &
                kWsExTopMost) !=
            0;
        const zFlags = kSwpNoMove | kSwpNoSize;
        win32.setWindowPos(
          nativeHandle,
          ffi.Pointer<ffi.Void>.fromAddress(kHwndTopMost),
          0,
          0,
          0,
          0,
          zFlags,
        );
        if (!wasTopMost) {
          win32.setWindowPos(
            nativeHandle,
            ffi.Pointer<ffi.Void>.fromAddress(kHwndNoTopMost),
            0,
            0,
            0,
            0,
            zFlags,
          );
        }
        win32.bringWindowToTop(nativeHandle);
        win32.setForegroundWindow(nativeHandle);
      }

      final focused = win32.getFocus();
      if (win32.getForegroundWindow().address == nativeHandle.address &&
          (focused == ffi.nullptr ||
              win32.getAncestor(focused, kGaRoot).address !=
                  nativeHandle.address)) {
        win32.setFocus(nativeHandle);
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWindowAdapter.focusNativeWindow',
        error,
        stackTrace,
      );
    }
  }

  @override
  void dispose() {
    _frameController.detach();
  }
}
