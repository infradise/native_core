import 'dart:async' show Timer;
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../../diagnostics.dart';
import '../../ffi/native_memory.dart';
import '../../models.dart';
import '../../window.dart';
import 'windows_win32_bindings.dart';

const int _topWindowSubclassId = 0x4E574331; // 'NWC1'
const int _childViewSubclassId = 0x4E574332; // 'NWC2'

/// Extracts `GET_X_LPARAM(lParam)` as a signed 16-bit screen X coordinate so
/// secondary monitors positioned to the left of the primary display (`x < 0`)
/// are handled accurately.
int decodeWin32SignedX(int lParam) => (lParam & 0xFFFF).toSigned(16);

/// Extracts `GET_Y_LPARAM(lParam)` as a signed 16-bit screen Y coordinate so
/// secondary monitors positioned above the primary display (`y < 0`) are
/// handled accurately.
int decodeWin32SignedY(int lParam) => ((lParam >> 16) & 0xFFFF).toSigned(16);

/// Computes the exact client rectangle for a maximized custom-frame Win32
/// window inside `WM_NCCALCSIZE`, preventing the 8px outer resize frame
/// overhang while keeping auto-hide taskbars accessible.
NativeRect computeWin32MaximizedClientRect({
  required NativeRect rawWindowRect,
  required NativeRect? monitorBounds,
  required NativeRect? monitorWorkArea,
  required int frameX,
  required int frameY,
}) {
  if (monitorWorkArea != null &&
      monitorWorkArea.width > 0 &&
      monitorWorkArea.height > 0) {
    var height = monitorWorkArea.height;
    if (monitorBounds != null && monitorWorkArea == monitorBounds) {
      // Auto-hide taskbar covers 0px of rcWork; leave 1px so moving the cursor
      // to the screen bottom still reveals the taskbar.
      height = height > 1 ? height - 1 : height;
    }
    return NativeRect(
      monitorWorkArea.left,
      monitorWorkArea.top,
      monitorWorkArea.width,
      height,
    );
  }

  final insetW = rawWindowRect.width - (frameX * 2);
  final insetH = rawWindowRect.height - (frameY * 2);
  return NativeRect(
    rawWindowRect.left + frameX,
    rawWindowRect.top + frameY,
    insetW > 1 ? insetW : rawWindowRect.width,
    insetH > 1 ? insetH : rawWindowRect.height,
  );
}

/// Computes the Win32 `WM_NCHITTEST` resize code (`HTLEFT`..`HTBOTTOMRIGHT`, or
/// `0` = `HTNOWHERE` for client content) for an unmaximized frameless window.
///
/// Always returns `0` when [isMaximized] is `true` so Fitts's Law top-right
/// corner clicks `(width - 1, 0)` reach custom close (`X`) controls.
int hitTestWin32ResizeBorder({
  required int screenX,
  required int screenY,
  required NativeRect windowRect,
  required int dpi,
  required bool isMaximized,
  required bool isFullScreen,
  required bool isHiddenTitleBar,
}) {
  if (!isHiddenTitleBar || isMaximized || isFullScreen) {
    return kHtNowhere;
  }
  final left = windowRect.left.round();
  final top = windowRect.top.round();
  final right = (windowRect.left + windowRect.width).round();
  final bottom = (windowRect.top + windowRect.height).round();
  if (screenX < left ||
      screenX >= right ||
      screenY < top ||
      screenY >= bottom) {
    return kHtNowhere;
  }

  final scale = (dpi > 0 ? dpi : 96) / 96.0;
  final edge = (6.0 * scale).round().clamp(4, 16);
  final topEdge = (4.0 * scale).round().clamp(3, 12);
  final corner = (12.0 * scale).round().clamp(8, 28);

  final inTop = screenY < top + topEdge;
  final inBottom = screenY >= bottom - edge;
  final inLeft = screenX < left + edge;
  final inRight = screenX >= right - edge;

  if ((inTop || inLeft) && screenY < top + corner && screenX < left + corner) {
    return kHtTopLeft;
  }
  if ((inTop || inRight) &&
      screenY < top + corner &&
      screenX >= right - corner) {
    return kHtTopRight;
  }
  if ((inBottom || inLeft) &&
      screenY >= bottom - corner &&
      screenX < left + corner) {
    return kHtBottomLeft;
  }
  if ((inBottom || inRight) &&
      screenY >= bottom - corner &&
      screenX >= right - corner) {
    return kHtBottomRight;
  }
  if (inTop) return kHtTop;
  if (inBottom) return kHtBottom;
  if (inLeft) return kHtLeft;
  if (inRight) return kHtRight;
  return kHtNowhere;
}

/// Decision produced when intercepting the initial `SWP_SHOWWINDOW` sent by
/// stock `flutter_window.cpp` (`SetNextFrameCallback` ->
/// `ShowWindow(SW_SHOWNORMAL)`).
class Win32InitialShowInterceptDecision {
  /// Creates a [Win32InitialShowInterceptDecision].
  const Win32InitialShowInterceptDecision({
    required this.consumedInitialShow,
    required this.updatedFlags,
    required this.postDeferredMaximize,
    required this.postDeferredFocus,
  });

  /// Whether this event consumed the initial pre-frame show gate.
  final bool consumedInitialShow;

  /// Updated `WINDOWPOS.flags` value.
  final int updatedFlags;

  /// Whether to post deferred `SW_SHOWMAXIMIZED` right after Frame #1.
  final bool postDeferredMaximize;

  /// Whether to post deferred foreground focus right after Frame #1.
  final bool postDeferredFocus;
}

/// Coordinates `native_core`'s deferred pre-`runApp` window configuration with
/// stock `flutter_window.cpp`'s `SetNextFrameCallback` (`SW_SHOWNORMAL`) so
/// host runner files never need modification.
Win32InitialShowInterceptDecision resolveWin32WindowPosShowIntercept({
  required bool deferInitialShow,
  required bool pendingShow,
  required bool pendingMaximize,
  required bool pendingFocus,
  required int windowPosFlags,
}) {
  if (!deferInitialShow || (windowPosFlags & kSwpShowWindow) == 0) {
    return Win32InitialShowInterceptDecision(
      consumedInitialShow: false,
      updatedFlags: windowPosFlags,
      postDeferredMaximize: false,
      postDeferredFocus: false,
    );
  }

  if (!pendingShow) {
    return Win32InitialShowInterceptDecision(
      consumedInitialShow: true,
      updatedFlags: windowPosFlags & ~kSwpShowWindow,
      postDeferredMaximize: false,
      postDeferredFocus: false,
    );
  }

  if (pendingMaximize) {
    return Win32InitialShowInterceptDecision(
      consumedInitialShow: true,
      updatedFlags: windowPosFlags & ~kSwpShowWindow,
      postDeferredMaximize: true,
      postDeferredFocus: pendingFocus,
    );
  }

  return Win32InitialShowInterceptDecision(
    consumedInitialShow: true,
    updatedFlags: windowPosFlags,
    postDeferredMaximize: false,
    postDeferredFocus: pendingFocus,
  );
}

/// Decision returned by [resolveWin32EraseBkgndAction] for `WM_ERASEBKGND` on
/// the top-level frame `HWND` and its child `FLUTTERVIEW` `HWND`.
class Win32EraseBkgndDecision {
  /// Creates a [Win32EraseBkgndDecision].
  const Win32EraseBkgndDecision({
    required this.intercept,
    required this.fillWithBrush,
  });

  /// Whether to swallow `WM_ERASEBKGND` (`return 1`) instead of calling
  /// `DefSubclassProc` (which would paint `WHITE_BRUSH`).
  final bool intercept;

  /// Whether to invoke GDI `FillRect` on the `HDC`.
  ///
  /// Must be `false` on a visible `FLUTTERVIEW` child `HWND` so synchronous CPU
  /// GDI drawing never dirties the DWM redirection bitmap in conflict with
  /// ANGLE's live Direct3D 11 / DXGI flip-model swapchain during resize.
  final bool fillWithBrush;
}

/// Resolves how `WM_ERASEBKGND` should be handled without causing either a
/// startup `#FFFFFF` `WHITE_BRUSH` flash or live DXGI resize strobe flicker.
Win32EraseBkgndDecision resolveWin32EraseBkgndAction({
  required TitleBarStyle titleBarStyle,
  required bool hasCustomBrush,
  required bool isWindowVisible,
  required bool isChildView,
}) {
  if (titleBarStyle != TitleBarStyle.hidden && !hasCustomBrush) {
    return const Win32EraseBkgndDecision(
      intercept: false,
      fillWithBrush: false,
    );
  }
  if (isChildView) {
    return Win32EraseBkgndDecision(
      intercept: true,
      fillWithBrush: !isWindowVisible,
    );
  }
  return Win32EraseBkgndDecision(
    intercept: true,
    fillWithBrush: !isWindowVisible || hasCustomBrush,
  );
}

/// Manages Win32 `SetWindowSubclass` hooks for a single `HWND` and its child
/// `FLUTTERVIEW`, delivering frameless custom caption bars, 8-direction resize,
/// `minimumSize` enforcement, `WHITE_BRUSH` flash suppression, and Frame #1
/// presentation coordination without touching `windows/runner/`.
class WindowsFrameController {
  /// Creates a [WindowsFrameController] for [hwnd].
  WindowsFrameController({
    required this.hwnd,
    required this.onApplyDeferredMaximize,
    required this.onApplyDeferredFocus,
  });

  static final Map<int, WindowsFrameController> _controllersByAddress =
      <int, WindowsFrameController>{};

  static final ffi.NativeCallable<Win32SubclassProcNative>
  _topSubclassCallable =
      ffi.NativeCallable<Win32SubclassProcNative>.isolateLocal(
        _onTopSubclass,
        exceptionalReturn: 0,
      );

  static final ffi.NativeCallable<Win32SubclassProcNative>
  _childSubclassCallable =
      ffi.NativeCallable<Win32SubclassProcNative>.isolateLocal(
        _onChildSubclass,
        exceptionalReturn: 0,
      );

  /// Target top-level Win32 `HWND`.
  final ffi.Pointer<ffi.Void> hwnd;

  /// Invoked when deferred `SW_SHOWMAXIMIZED` fires at Frame #1.
  final void Function() onApplyDeferredMaximize;

  /// Invoked when deferred foreground focus fires at Frame #1.
  final void Function() onApplyDeferredFocus;

  /// Current [TitleBarStyle].
  TitleBarStyle titleBarStyle = TitleBarStyle.normal;

  /// Whether fullscreen mode is active.
  bool isFullScreen = false;

  /// Minimum interactive resize dimensions enforced via `WM_GETMINMAXINFO`.
  NativeSize minimumSize = const NativeSize(500, 300);

  bool _topSubclassed = false;
  bool _childSubclassed = false;
  ffi.Pointer<ffi.Void> _childHwnd = ffi.nullptr;
  ffi.Pointer<ffi.Void> _customBgBrush = ffi.nullptr;
  int _removedTopClassRedrawBits = 0;
  int _removedChildClassRedrawBits = 0;
  int _savedChildClassBgBrush = 0;

  bool _deferInitialShow = false;
  bool _pendingShow = false;
  bool _pendingMaximize = false;
  bool _pendingFocus = false;
  bool _fallbackScheduled = false;
  Timer? _firstFrameFallbackTimer;

  /// Whether pre-Frame-#1 `ShowWindow` deferral is currently active.
  bool get isDeferringInitialShow => _deferInitialShow;

  /// Logical pending visibility while [isDeferringInitialShow] is `true`.
  bool get pendingShow => _pendingShow;

  /// Logical pending maximized state while [isDeferringInitialShow] is `true`.
  bool get pendingMaximize => _pendingMaximize;

  /// Attaches `SetWindowSubclass` to [hwnd] (and its child `FLUTTERVIEW` if
  /// already created) when called on [hwnd]'s owning UI thread.
  void attach() {
    if (hwnd == ffi.nullptr) return;
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return;

    try {
      if (win32.isWindow(hwnd) == 0) return;

      final selfTid = win32.getCurrentThreadId();
      final winTid = win32.getWindowThreadProcessId(hwnd, ffi.nullptr);
      if (selfTid == 0 || selfTid != winTid) return;

      _controllersByAddress[hwnd.address] = this;

      if (win32.isWindowVisible(hwnd) == 0) {
        _deferInitialShow = true;
      }

      if (!_topSubclassed) {
        final ok = win32.setWindowSubclass(
          hwnd,
          _topSubclassCallable.nativeFunction,
          _topWindowSubclassId,
          hwnd.address,
        );
        _topSubclassed = ok != 0;
      }
      if (_topSubclassed) {
        _stabilizeTopWindowForGpuResize(win32);
      }
      _ensureChildViewSubclassed(win32);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsFrameController.attach',
        error,
        stackTrace,
      );
    }
  }

  /// Updates the GDI solid brush used during `WM_ERASEBKGND`.
  void setBackgroundColor(NativeColor color) {
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null || hwnd == ffi.nullptr) return;
    try {
      if (_customBgBrush != ffi.nullptr) {
        win32.deleteObject(_customBgBrush);
        _customBgBrush = ffi.nullptr;
      }
      final alpha = (color.argb >> 24) & 0xFF;
      if (alpha > 0) {
        final r = (color.argb >> 16) & 0xFF;
        final g = (color.argb >> 8) & 0xFF;
        final b = color.argb & 0xFF;
        // Win32 COLORREF layout is 0x00BBGGRR.
        final colorRef = (b << 16) | (g << 8) | r;
        _customBgBrush = win32.createSolidBrush(colorRef);
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsFrameController.setBackgroundColor',
        error,
        stackTrace,
      );
    }
  }

  /// Applies [style] (`TitleBarStyle.hidden` vs `TitleBarStyle.normal`) using
  /// DWM attributes and `SWP_FRAMECHANGED`.
  void applyTitleBarStyle(TitleBarStyle style) {
    titleBarStyle = style;
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null || hwnd == ffi.nullptr) return;
    try {
      if (win32.isWindow(hwnd) == 0) return;
      if (!_topSubclassed) attach();

      final hidden = style == TitleBarStyle.hidden;
      if (_topSubclassed) {
        final curStyle = win32.getWindowLongPtrW(hwnd, kGwlStyle);
        final desiredStyle =
            curStyle |
            kWsClipChildren |
            kWsClipSiblings |
            kWsThickFrame |
            kWsCaption |
            kWsSysMenu |
            kWsMaximizeBox |
            kWsMinimizeBox;
        if (desiredStyle != curStyle) {
          win32.setWindowLongPtrW(hwnd, kGwlStyle, desiredStyle);
        }

        if (hidden) {
          win32.scratchInt32.value = 1;
          win32.dwmSetWindowAttribute(
            hwnd,
            kDwmwaUseImmersiveDarkMode,
            win32.scratchInt32.cast(),
            4,
          );
          win32.scratchInt32.value = kDwmwcpRound;
          win32.dwmSetWindowAttribute(
            hwnd,
            kDwmwaWindowCornerPreference,
            win32.scratchInt32.cast(),
            4,
          );
          win32.scratchMargins.ref
            ..cxLeftWidth = 0
            ..cxRightWidth = 0
            ..cyTopHeight = 0
            ..cyBottomHeight = 1;
          win32.dwmExtendFrameIntoClientArea(hwnd, win32.scratchMargins);
        } else {
          win32.scratchInt32.value = kDwmwcpDefault;
          win32.dwmSetWindowAttribute(
            hwnd,
            kDwmwaWindowCornerPreference,
            win32.scratchInt32.cast(),
            4,
          );
          win32.scratchMargins.ref
            ..cxLeftWidth = 0
            ..cxRightWidth = 0
            ..cyTopHeight = 0
            ..cyBottomHeight = 0;
          win32.dwmExtendFrameIntoClientArea(hwnd, win32.scratchMargins);
        }
      } else {
        final curStyle = win32.getWindowLongPtrW(hwnd, kGwlStyle);
        final targetStyle =
            hidden
                ? (((curStyle & ~kWsCaption) | kWsThickFrame) |
                    kWsClipChildren |
                    kWsClipSiblings)
                : (curStyle |
                    kWsCaption |
                    kWsThickFrame |
                    kWsClipChildren |
                    kWsClipSiblings);
        if (targetStyle != curStyle) {
          win32.setWindowLongPtrW(hwnd, kGwlStyle, targetStyle);
        }
      }

      win32.setWindowPos(
        hwnd,
        ffi.nullptr,
        0,
        0,
        0,
        0,
        kSwpFrameChanged |
            kSwpNoMove |
            kSwpNoSize |
            kSwpNoZOrder |
            kSwpNoActivate,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsFrameController.applyTitleBarStyle',
        error,
        stackTrace,
      );
    }
  }

  /// Queues a pre-Frame-#1 `maximize()` (`true` if deferred, `false` if caller
  /// should invoke `ShowWindow(SW_SHOWMAXIMIZED)` immediately).
  bool recordMaximizeIfDeferred() {
    if (!_deferInitialShow) return false;
    _pendingMaximize = true;
    _scheduleFirstFrameFallback();
    return true;
  }

  /// Clears pending maximize when `unmaximize()` is called prior to Frame #1.
  bool recordUnmaximizeIfDeferred() {
    if (!_deferInitialShow) return false;
    _pendingMaximize = false;
    return true;
  }

  /// Cancels initial-show deferral when `minimize()` is invoked explicitly.
  void cancelDeferralForMinimize() {
    _deferInitialShow = false;
  }

  /// Queues a pre-Frame-#1 `show()` (`true` if deferred).
  bool recordShowIfDeferred() {
    if (!_deferInitialShow) return false;
    _pendingShow = true;
    _scheduleFirstFrameFallback();
    return true;
  }

  /// Clears pending show/focus when `hide()` is called prior to Frame #1.
  bool recordHideIfDeferred() {
    if (!_deferInitialShow) return false;
    _pendingShow = false;
    _pendingFocus = false;
    return true;
  }

  /// Queues a pre-Frame-#1 `focus()` (`true` if deferred).
  bool recordFocusIfDeferred() {
    if (!_deferInitialShow) return false;
    _pendingFocus = true;
    return true;
  }

  void _scheduleFirstFrameFallback() {
    if (_fallbackScheduled || !_deferInitialShow) return;
    _fallbackScheduled = true;
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _firstFrameFallbackTimer?.cancel();
        _firstFrameFallbackTimer = Timer(const Duration(milliseconds: 60), () {
          if (!_deferInitialShow || hwnd == ffi.nullptr) return;
          _deferInitialShow = false;
          if (_pendingShow) {
            final win32 = WindowsWin32Bindings.instance;
            win32?.showWindow(
              hwnd,
              _pendingMaximize ? kSwShowMaximized : kSwShow,
            );
            if (_pendingFocus) {
              onApplyDeferredFocus();
            }
          }
        });
      });
    } catch (_) {
      _fallbackScheduled = false;
    }
  }

  void _stabilizeTopWindowForGpuResize(WindowsWin32Bindings win32) {
    if (hwnd == ffi.nullptr || win32.isWindow(hwnd) == 0) return;
    final curStyle = win32.getWindowLongPtrW(hwnd, kGwlStyle);
    final clippedStyle = curStyle | kWsClipChildren | kWsClipSiblings;
    if (clippedStyle != curStyle) {
      win32.setWindowLongPtrW(hwnd, kGwlStyle, clippedStyle);
    }

    final classStyle = win32.getClassLongPtrW(hwnd, kGclStyle);
    final redrawBits = classStyle & (kCsHRedraw | kCsVRedraw);
    if (redrawBits != 0) {
      _removedTopClassRedrawBits |= redrawBits;
      win32.setClassLongPtrW(
        hwnd,
        kGclStyle,
        classStyle & ~(kCsHRedraw | kCsVRedraw),
      );
    }
  }

  void _ensureChildViewSubclassed(WindowsWin32Bindings win32) {
    if (hwnd == ffi.nullptr) return;
    if (_childSubclassed &&
        _childHwnd != ffi.nullptr &&
        win32.isWindow(_childHwnd) != 0) {
      return;
    }
    final child = win32.getWindow(hwnd, kGwChild);
    if (child == ffi.nullptr || win32.isWindow(child) == 0) return;
    final selfTid = win32.getCurrentThreadId();
    if (win32.getWindowThreadProcessId(child, ffi.nullptr) != selfTid) return;

    final ok = win32.setWindowSubclass(
      child,
      _childSubclassCallable.nativeFunction,
      _childViewSubclassId,
      hwnd.address,
    );
    if (ok != 0) {
      _childHwnd = child;
      _childSubclassed = true;

      final childClassStyle = win32.getClassLongPtrW(child, kGclStyle);
      final redrawBits = childClassStyle & (kCsHRedraw | kCsVRedraw);
      if (redrawBits != 0) {
        _removedChildClassRedrawBits |= redrawBits;
        win32.setClassLongPtrW(
          child,
          kGclStyle,
          childClassStyle & ~(kCsHRedraw | kCsVRedraw),
        );
      }

      final childBgBrush = win32.getClassLongPtrW(child, kGclpHbrBackground);
      if (childBgBrush != 0) {
        _savedChildClassBgBrush = childBgBrush;
        win32.setClassLongPtrW(child, kGclpHbrBackground, 0);
      }
    }
  }

  /// Detaches top-level and child Win32 subclasses and frees custom GDI brushes
  /// strictly BEFORE `DestroyWindow` / `DefSubclassProc(WM_DESTROY)`.
  void detach() {
    _firstFrameFallbackTimer?.cancel();
    _firstFrameFallbackTimer = null;
    _controllersByAddress.remove(hwnd.address);

    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return;
    try {
      if (_childSubclassed && _childHwnd != ffi.nullptr) {
        if (win32.isWindow(_childHwnd) != 0) {
          if (_removedChildClassRedrawBits != 0) {
            final cur = win32.getClassLongPtrW(_childHwnd, kGclStyle);
            win32.setClassLongPtrW(
              _childHwnd,
              kGclStyle,
              cur | _removedChildClassRedrawBits,
            );
          }
          if (_savedChildClassBgBrush != 0) {
            win32.setClassLongPtrW(
              _childHwnd,
              kGclpHbrBackground,
              _savedChildClassBgBrush,
            );
          }
          win32.removeWindowSubclass(
            _childHwnd,
            _childSubclassCallable.nativeFunction,
            _childViewSubclassId,
          );
        }
        _removedChildClassRedrawBits = 0;
        _savedChildClassBgBrush = 0;
        _childSubclassed = false;
        _childHwnd = ffi.nullptr;
      }
      if (_topSubclassed && hwnd != ffi.nullptr) {
        if (win32.isWindow(hwnd) != 0) {
          if (_removedTopClassRedrawBits != 0) {
            final cur = win32.getClassLongPtrW(hwnd, kGclStyle);
            win32.setClassLongPtrW(
              hwnd,
              kGclStyle,
              cur | _removedTopClassRedrawBits,
            );
          }
          win32.removeWindowSubclass(
            hwnd,
            _topSubclassCallable.nativeFunction,
            _topWindowSubclassId,
          );
        }
        _removedTopClassRedrawBits = 0;
        _topSubclassed = false;
      }
      if (_customBgBrush != ffi.nullptr) {
        win32.deleteObject(_customBgBrush);
        _customBgBrush = ffi.nullptr;
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsFrameController.detach',
        error,
        stackTrace,
      );
    }
  }

  static int _onTopSubclass(
    ffi.Pointer<ffi.Void> hwnd,
    int msg,
    int wParam,
    int lParam,
    int uIdSubclass,
    int dwRefData,
  ) {
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return 0;

    final controller = _controllersByAddress[dwRefData];
    if (msg == kWmDestroy) {
      // Detach BEFORE DefSubclassProc runs FlutterWindow::OnDestroy() (which
      // tears down the Dart isolate prior to WM_NCDESTROY).
      if (controller != null) {
        controller.detach();
      } else {
        win32.removeWindowSubclass(
          hwnd,
          _topSubclassCallable.nativeFunction,
          uIdSubclass,
        );
      }
      return win32.defSubclassProc(hwnd, msg, wParam, lParam);
    }

    if (controller == null) {
      win32.removeWindowSubclass(
        hwnd,
        _topSubclassCallable.nativeFunction,
        uIdSubclass,
      );
      return win32.defSubclassProc(hwnd, msg, wParam, lParam);
    }

    return controller._handleTopMessage(win32, hwnd, msg, wParam, lParam);
  }

  static int _onChildSubclass(
    ffi.Pointer<ffi.Void> childHwnd,
    int msg,
    int wParam,
    int lParam,
    int uIdSubclass,
    int dwRefData,
  ) {
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return 0;

    final controller = _controllersByAddress[dwRefData];
    if (msg == kWmDestroy || controller == null) {
      win32.removeWindowSubclass(
        childHwnd,
        _childSubclassCallable.nativeFunction,
        uIdSubclass,
      );
      if (controller != null && controller._childHwnd == childHwnd) {
        controller._childSubclassed = false;
        controller._childHwnd = ffi.nullptr;
      }
      return win32.defSubclassProc(childHwnd, msg, wParam, lParam);
    }

    return controller._handleChildMessage(
      win32,
      childHwnd,
      msg,
      wParam,
      lParam,
    );
  }

  int _handleTopMessage(
    WindowsWin32Bindings win32,
    ffi.Pointer<ffi.Void> targetHwnd,
    int msg,
    int wParam,
    int lParam,
  ) {
    switch (msg) {
      case kWmNcCalcSize:
        if (titleBarStyle == TitleBarStyle.hidden &&
            wParam != 0 &&
            lParam != 0) {
          final rgrc0 = ffi.Pointer<Win32Rect>.fromAddress(lParam);
          if (win32.isZoomed(targetHwnd) != 0 && !isFullScreen) {
            final dpi = win32.getDpiForWindow(targetHwnd);
            final frameX =
                win32.getSystemMetricsForDpi(kSmCxSizeFrame, dpi) +
                win32.getSystemMetricsForDpi(kSmCxPaddedBorder, dpi);
            final frameY =
                win32.getSystemMetricsForDpi(kSmCySizeFrame, dpi) +
                win32.getSystemMetricsForDpi(kSmCxPaddedBorder, dpi);

            NativeRect? monitorBounds;
            NativeRect? monitorWork;
            final monitor = win32.monitorFromWindow(
              targetHwnd,
              kMonitorDefaultToNearest,
            );
            if (monitor != ffi.nullptr) {
              win32.scratchMonitorInfo.ref.cbSize =
                  ffi.sizeOf<Win32MonitorInfo>();
              if (win32.getMonitorInfoW(monitor, win32.scratchMonitorInfo) !=
                  0) {
                final m = win32.scratchMonitorInfo.ref.rcMonitor;
                final w = win32.scratchMonitorInfo.ref.rcWork;
                monitorBounds = NativeRect(
                  m.left.toDouble(),
                  m.top.toDouble(),
                  (m.right - m.left).toDouble(),
                  (m.bottom - m.top).toDouble(),
                );
                monitorWork = NativeRect(
                  w.left.toDouble(),
                  w.top.toDouble(),
                  (w.right - w.left).toDouble(),
                  (w.bottom - w.top).toDouble(),
                );
              }
            }

            final raw = NativeRect(
              rgrc0.ref.left.toDouble(),
              rgrc0.ref.top.toDouble(),
              (rgrc0.ref.right - rgrc0.ref.left).toDouble(),
              (rgrc0.ref.bottom - rgrc0.ref.top).toDouble(),
            );
            final adjusted = computeWin32MaximizedClientRect(
              rawWindowRect: raw,
              monitorBounds: monitorBounds,
              monitorWorkArea: monitorWork,
              frameX: frameX,
              frameY: frameY,
            );
            rgrc0.ref
              ..left = adjusted.left.round()
              ..top = adjusted.top.round()
              ..right = (adjusted.left + adjusted.width).round()
              ..bottom = (adjusted.top + adjusted.height).round();
          }
          return 0;
        }

      case kWmNcHitTest:
        if (titleBarStyle == TitleBarStyle.hidden &&
            win32.isZoomed(targetHwnd) == 0 &&
            !isFullScreen) {
          if (win32.getWindowRect(targetHwnd, win32.scratchRect) != 0) {
            final r = win32.scratchRect.ref;
            final hit = hitTestWin32ResizeBorder(
              screenX: decodeWin32SignedX(lParam),
              screenY: decodeWin32SignedY(lParam),
              windowRect: NativeRect(
                r.left.toDouble(),
                r.top.toDouble(),
                (r.right - r.left).toDouble(),
                (r.bottom - r.top).toDouble(),
              ),
              dpi: win32.getDpiForWindow(targetHwnd),
              isMaximized: false,
              isFullScreen: false,
              isHiddenTitleBar: true,
            );
            if (hit != kHtNowhere) {
              return hit;
            }
          }
        }

      case kWmGetMinMaxInfo:
        if (lParam != 0) {
          final res = win32.defSubclassProc(targetHwnd, msg, wParam, lParam);
          final info = ffi.Pointer<Win32MinMaxInfo>.fromAddress(lParam);
          final minW = minimumSize.width.round();
          final minH = minimumSize.height.round();
          if (minW > 0) info.ref.ptMinTrackSize.x = minW;
          if (minH > 0) info.ref.ptMinTrackSize.y = minH;
          return res;
        }

      case kWmWindowPosChanging:
        if (_deferInitialShow && lParam != 0) {
          final pos = ffi.Pointer<Win32WindowPos>.fromAddress(lParam);
          final decision = resolveWin32WindowPosShowIntercept(
            deferInitialShow: _deferInitialShow,
            pendingShow: _pendingShow,
            pendingMaximize: _pendingMaximize,
            pendingFocus: _pendingFocus,
            windowPosFlags: pos.ref.flags,
          );
          if (decision.consumedInitialShow) {
            _deferInitialShow = false;
            _firstFrameFallbackTimer?.cancel();
            _firstFrameFallbackTimer = null;
            pos.ref.flags = decision.updatedFlags;
            if (decision.postDeferredMaximize || decision.postDeferredFocus) {
              win32.postMessageW(
                targetHwnd,
                kWmApplyDeferredWin32Show,
                decision.postDeferredMaximize ? 1 : 0,
                decision.postDeferredFocus ? 1 : 0,
              );
            }
          }
        }

      case kWmApplyDeferredWin32Show:
        if (wParam == 1) {
          onApplyDeferredMaximize();
        }
        if (lParam == 1) {
          onApplyDeferredFocus();
        }
        return 0;

      case kWmEraseBkgnd:
        final decision = resolveWin32EraseBkgndAction(
          titleBarStyle: titleBarStyle,
          hasCustomBrush: _customBgBrush != ffi.nullptr,
          isWindowVisible: win32.isWindowVisible(targetHwnd) != 0,
          isChildView: false,
        );
        if (decision.intercept) {
          if (decision.fillWithBrush && wParam != 0) {
            final brush =
                _customBgBrush != ffi.nullptr
                    ? _customBgBrush
                    : win32.darkFallbackBrush;
            if (brush != ffi.nullptr &&
                win32.getClientRect(targetHwnd, win32.scratchRect) != 0) {
              win32.fillRect(
                ffi.Pointer<ffi.Void>.fromAddress(wParam),
                win32.scratchRect,
                brush,
              );
            }
          }
          return 1;
        }

      case kWmSize:
        _ensureChildViewSubclassed(win32);

      case kWmParentNotify:
        if ((wParam & 0xFFFF) == kWmCreate) {
          _ensureChildViewSubclassed(win32);
        }
    }
    return win32.defSubclassProc(targetHwnd, msg, wParam, lParam);
  }

  int _handleChildMessage(
    WindowsWin32Bindings win32,
    ffi.Pointer<ffi.Void> childHwnd,
    int msg,
    int wParam,
    int lParam,
  ) {
    switch (msg) {
      case kWmNcHitTest:
        if (titleBarStyle == TitleBarStyle.hidden &&
            hwnd != ffi.nullptr &&
            win32.isZoomed(hwnd) == 0 &&
            !isFullScreen) {
          if (win32.getWindowRect(hwnd, win32.scratchRect) != 0) {
            final r = win32.scratchRect.ref;
            final hit = hitTestWin32ResizeBorder(
              screenX: decodeWin32SignedX(lParam),
              screenY: decodeWin32SignedY(lParam),
              windowRect: NativeRect(
                r.left.toDouble(),
                r.top.toDouble(),
                (r.right - r.left).toDouble(),
                (r.bottom - r.top).toDouble(),
              ),
              dpi: win32.getDpiForWindow(hwnd),
              isMaximized: false,
              isFullScreen: false,
              isHiddenTitleBar: true,
            );
            if (hit != kHtNowhere) {
              return kHtTransparent;
            }
          }
        }

      case kWmEraseBkgnd:
        final visible = hwnd != ffi.nullptr && win32.isWindowVisible(hwnd) != 0;
        final decision = resolveWin32EraseBkgndAction(
          titleBarStyle: titleBarStyle,
          hasCustomBrush: _customBgBrush != ffi.nullptr,
          isWindowVisible: visible,
          isChildView: true,
        );
        if (decision.intercept) {
          if (decision.fillWithBrush && wParam != 0) {
            final brush =
                _customBgBrush != ffi.nullptr
                    ? _customBgBrush
                    : win32.darkFallbackBrush;
            if (brush != ffi.nullptr &&
                win32.getClientRect(childHwnd, win32.scratchRect) != 0) {
              win32.fillRect(
                ffi.Pointer<ffi.Void>.fromAddress(wParam),
                win32.scratchRect,
                brush,
              );
            }
          }
          return 1;
        }
    }
    return win32.defSubclassProc(childHwnd, msg, wParam, lParam);
  }
}

/// Snapshot returned by [debugRunWin32FramelessProbe] on Windows to verify real
/// Win32 `SetWindowSubclass` (`WM_NCCALCSIZE`, `WM_GETMINMAXINFO`,
/// `WM_WINDOWPOSCHANGING`, and `WM_DESTROY` teardown) against `user32.dll`.
class Win32FramelessProbeResult {
  /// Creates a [Win32FramelessProbeResult].
  const Win32FramelessProbeResult({
    required this.windowHeightBefore,
    required this.clientHeightBefore,
    required this.windowWidthHidden,
    required this.windowHeightHidden,
    required this.clientWidthHidden,
    required this.clientHeightHidden,
    required this.clientHeightRestored,
    required this.minTrackWidth,
    required this.minTrackHeight,
    required this.deferredBeforeShow,
    required this.hasClipChildrenStyle,
    required this.classRedrawStripped,
  });

  /// Outer window height prior to `TitleBarStyle.hidden`.
  final int windowHeightBefore;

  /// Client height prior to `TitleBarStyle.hidden`.
  final int clientHeightBefore;

  /// Outer window width after `TitleBarStyle.hidden`.
  final int windowWidthHidden;

  /// Outer window height after `TitleBarStyle.hidden`.
  final int windowHeightHidden;

  /// Client width after `TitleBarStyle.hidden`.
  final int clientWidthHidden;

  /// Client height after `TitleBarStyle.hidden`.
  final int clientHeightHidden;

  /// Client height after restoring `TitleBarStyle.normal`.
  final int clientHeightRestored;

  /// Enforced `ptMinTrackSize.x` reported by `WM_GETMINMAXINFO`.
  final int minTrackWidth;

  /// Enforced `ptMinTrackSize.y` reported by `WM_GETMINMAXINFO`.
  final int minTrackHeight;

  /// Whether OS-level `ShowWindow` was deferred while logical state updated.
  final bool deferredBeforeShow;

  /// Whether `WS_CLIPCHILDREN` was applied to prevent parent GDI overdraw onto
  /// child `FLUTTERVIEW` during resize.
  final bool hasClipChildrenStyle;

  /// Whether `CS_HREDRAW | CS_VREDRAW` bits were stripped from the window class
  /// while attached.
  final bool classRedrawStripped;
}

/// Creates a real off-screen Win32 `WS_OVERLAPPEDWINDOW` on Windows, exercises
/// `Window.titleBarStyle` (`hidden` -> `normal`), `Window.minimumSize`, and
/// deferred initial `show()`, then destroys the window to verify clean
/// `WM_DESTROY` subclass removal. Returns `null` on non-Windows platforms.
Win32FramelessProbeResult? debugRunWin32FramelessProbe() {
  if (!Platform.isWindows) return null;
  final win32 = WindowsWin32Bindings.instance;
  if (win32 == null) return null;

  final hInstance = win32.getModuleHandleW(ffi.nullptr);
  final hwnd = NativeMemory.withUtf16WString('STATIC', (clsPtr) {
    return NativeMemory.withUtf16WString('NativeCoreProbe', (titlePtr) {
      return win32.createWindowExW(
        0,
        clsPtr,
        titlePtr,
        kWsOverlappedWindow,
        100,
        100,
        800,
        600,
        ffi.nullptr,
        ffi.nullptr,
        hInstance,
        ffi.nullptr,
      );
    });
  });
  if (hwnd == ffi.nullptr) return null;

  final winRect =
      NativeMemory.malloc(ffi.sizeOf<Win32Rect>()).cast<Win32Rect>();
  final cliRect =
      NativeMemory.malloc(ffi.sizeOf<Win32Rect>()).cast<Win32Rect>();
  final mmi =
      NativeMemory.malloc(
        ffi.sizeOf<Win32MinMaxInfo>(),
      ).cast<Win32MinMaxInfo>();
  Window? wrapped;
  try {
    win32.getWindowRect(hwnd, winRect);
    win32.getClientRect(hwnd, cliRect);
    final winHBefore = winRect.ref.bottom - winRect.ref.top;
    final cliHBefore = cliRect.ref.bottom - cliRect.ref.top;

    wrapped = Window.createWithNativeWindow(hwnd);
    wrapped
      ..titleBarStyle = TitleBarStyle.hidden
      ..minimumSize = const NativeSize(640, 420)
      ..backgroundColor = const NativeColor(0xFF111618)
      ..maximize()
      ..show();

    final stillHiddenOnOs = win32.isWindowVisible(hwnd) == 0;
    final hasClipChildren =
        (win32.getWindowLongPtrW(hwnd, kGwlStyle) & kWsClipChildren) != 0;
    final classRedrawCleared =
        (win32.getClassLongPtrW(hwnd, kGclStyle) & (kCsHRedraw | kCsVRedraw)) ==
        0;

    win32.getWindowRect(hwnd, winRect);
    win32.getClientRect(hwnd, cliRect);
    final winWHidden = winRect.ref.right - winRect.ref.left;
    final winHHidden = winRect.ref.bottom - winRect.ref.top;
    final cliWHidden = cliRect.ref.right - cliRect.ref.left;
    final cliHHidden = cliRect.ref.bottom - cliRect.ref.top;

    mmi.ref.ptMinTrackSize
      ..x = 0
      ..y = 0;
    win32.sendMessageW(hwnd, kWmGetMinMaxInfo, 0, mmi.address);
    final minW = mmi.ref.ptMinTrackSize.x;
    final minH = mmi.ref.ptMinTrackSize.y;

    wrapped.titleBarStyle = TitleBarStyle.normal;
    win32.getClientRect(hwnd, cliRect);
    final cliHRestored = cliRect.ref.bottom - cliRect.ref.top;

    return Win32FramelessProbeResult(
      windowHeightBefore: winHBefore,
      clientHeightBefore: cliHBefore,
      windowWidthHidden: winWHidden,
      windowHeightHidden: winHHidden,
      clientWidthHidden: cliWHidden,
      clientHeightHidden: cliHHidden,
      clientHeightRestored: cliHRestored,
      minTrackWidth: minW,
      minTrackHeight: minH,
      deferredBeforeShow:
          stillHiddenOnOs && wrapped.isMaximized && wrapped.isVisible,
      hasClipChildrenStyle: hasClipChildren,
      classRedrawStripped: classRedrawCleared,
    );
  } finally {
    wrapped?.dispose();
    if (win32.isWindow(hwnd) != 0) {
      win32.destroyWindow(hwnd);
    }
    NativeMemory.free(mmi.cast());
    NativeMemory.free(cliRect.cast());
    NativeMemory.free(winRect.cast());
  }
}
