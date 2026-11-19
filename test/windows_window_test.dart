import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_core/native_core.dart';
// ignore: implementation_imports
import 'package:native_core/src/testing/native_core_testing.dart';

class _FakeWindow {
  _FakeWindow({required this.id, required this.nativeHandle});

  final int id;
  final int nativeHandle;
  bool disposed = false;
}

void main() {
  group('Windows Win32 HWND resolution, frameless subclass, and displays', () {
    test(
      'WindowsMainWindowCache caches registered window while alive and re-resolves after destroy',
      () {
        final cache = WindowsMainWindowCache<_FakeWindow>();
        final currentHwnd = Pointer<Void>.fromAddress(0x11110000);
        var alive = true;
        var wrapCalls = 0;

        _FakeWindow? resolveOnce() => cache.resolve(
          findHandle: () => alive ? currentHwnd : null,
          isHandleAlive: (h) => alive && h.address == currentHwnd.address,
          wrapHandle: (_) {
            wrapCalls++;
            return _FakeWindow(id: 1, nativeHandle: 10 + wrapCalls);
          },
          lookupRegistered:
              (probe) => _FakeWindow(id: probe.id, nativeHandle: 999),
          sameBackingHandle: (a, b) => a.nativeHandle == b.nativeHandle,
          disposeProbe: (probe) => probe.disposed = true,
        );

        final first = resolveOnce();
        expect(first, isNotNull);
        expect(first!.nativeHandle, 999);
        expect(wrapCalls, 1);

        final second = resolveOnce();
        expect(identical(second, first), isTrue);
        expect(wrapCalls, 1);

        alive = false;
        expect(resolveOnce(), isNull);
      },
    );

    test(
      'decodeWin32SignedX/Y and hitTestWin32ResizeBorder support negative multi-monitor coords and preserve Fitts-Law maximized top-right click',
      () {
        const packedNegative = ((-300 & 0xFFFF) << 16) | (-1200 & 0xFFFF);
        expect(decodeWin32SignedX(packedNegative), equals(-1200));
        expect(decodeWin32SignedY(packedNegative), equals(-300));

        const winRect = NativeRect(-1200, -300, 800, 600);
        expect(
          hitTestWin32ResizeBorder(
            screenX: -1198,
            screenY: -298,
            windowRect: winRect,
            dpi: 96,
            isMaximized: false,
            isFullScreen: false,
            isHiddenTitleBar: true,
          ),
          equals(13),
        );
        expect(
          hitTestWin32ResizeBorder(
            screenX: -402,
            screenY: -299,
            windowRect: winRect,
            dpi: 96,
            isMaximized: false,
            isFullScreen: false,
            isHiddenTitleBar: true,
          ),
          equals(14),
        );
        expect(
          hitTestWin32ResizeBorder(
            screenX: -800,
            screenY: -280,
            windowRect: winRect,
            dpi: 96,
            isMaximized: false,
            isFullScreen: false,
            isHiddenTitleBar: true,
          ),
          equals(0),
        );
        expect(
          hitTestWin32ResizeBorder(
            screenX: -401,
            screenY: -300,
            windowRect: winRect,
            dpi: 96,
            isMaximized: true,
            isFullScreen: false,
            isHiddenTitleBar: true,
          ),
          equals(0),
        );
      },
    );

    test(
      'computeWin32MaximizedClientRect clamps to monitor workArea and leaves 1px for auto-hide taskbar',
      () {
        const rawOverhang = NativeRect(-8, -8, 1936, 1056);
        const monitor = NativeRect(0, 0, 1920, 1080);
        const workNormal = NativeRect(0, 0, 1920, 1040);
        expect(
          computeWin32MaximizedClientRect(
            rawWindowRect: rawOverhang,
            monitorBounds: monitor,
            monitorWorkArea: workNormal,
            frameX: 8,
            frameY: 8,
          ),
          equals(workNormal),
        );

        expect(
          computeWin32MaximizedClientRect(
            rawWindowRect: const NativeRect(-8, -8, 1936, 1096),
            monitorBounds: monitor,
            monitorWorkArea: monitor,
            frameX: 8,
            frameY: 8,
          ),
          equals(const NativeRect(0, 0, 1920, 1079)),
        );
      },
    );

    test(
      'resolveWin32WindowPosShowIntercept prevents white flash and neutralizes runner SW_SHOWNORMAL un-maximize',
      () {
        const swpShowWindow = 0x0040;
        const baseFlags = 0x0001 | 0x0002 | swpShowWindow;

        final maxDecision = resolveWin32WindowPosShowIntercept(
          deferInitialShow: true,
          pendingShow: true,
          pendingMaximize: true,
          pendingFocus: true,
          windowPosFlags: baseFlags,
        );
        expect(maxDecision.consumedInitialShow, isTrue);
        expect(maxDecision.updatedFlags & swpShowWindow, equals(0));
        expect(maxDecision.postDeferredMaximize, isTrue);
        expect(maxDecision.postDeferredFocus, isTrue);

        final normalDecision = resolveWin32WindowPosShowIntercept(
          deferInitialShow: true,
          pendingShow: true,
          pendingMaximize: false,
          pendingFocus: true,
          windowPosFlags: baseFlags,
        );
        expect(normalDecision.consumedInitialShow, isTrue);
        expect(
          normalDecision.updatedFlags & swpShowWindow,
          equals(swpShowWindow),
        );
        expect(normalDecision.postDeferredMaximize, isFalse);
        expect(normalDecision.postDeferredFocus, isTrue);

        final hiddenDecision = resolveWin32WindowPosShowIntercept(
          deferInitialShow: true,
          pendingShow: false,
          pendingMaximize: false,
          pendingFocus: false,
          windowPosFlags: baseFlags,
        );
        expect(hiddenDecision.consumedInitialShow, isTrue);
        expect(hiddenDecision.updatedFlags & swpShowWindow, equals(0));
        expect(hiddenDecision.postDeferredMaximize, isFalse);
      },
    );

    test(
      'DisplayManager.instance.getAll enumerates live Win32 monitors with workArea and scaleFactor on Windows',
      () {
        if (!Platform.isWindows) return;
        final displays = DisplayManager.instance.getAll();
        expect(displays, isNotEmpty);
        expect(displays.first.id, equals(0));
        expect(displays.first.bounds.width, greaterThan(0));
        expect(displays.first.bounds.height, greaterThan(0));
        expect(displays.first.workArea.width, greaterThan(0));
        expect(displays.first.workArea.height, greaterThan(0));
        expect(displays.first.scaleFactor, greaterThan(0));
      },
    );

    test(
      'Win32 live HWND SetWindowSubclass removes native caption bar, enforces minimumSize, defers pre-frame show, and tears down cleanly',
      () {
        if (!Platform.isWindows) return;
        final probe = debugRunWin32FramelessProbe();
        expect(probe, isNotNull);
        expect(probe!.clientHeightBefore, lessThan(probe.windowHeightBefore));
        expect(probe.clientWidthHidden, equals(probe.windowWidthHidden));
        expect(probe.clientHeightHidden, equals(probe.windowHeightHidden));
        expect(probe.minTrackWidth, equals(640));
        expect(probe.minTrackHeight, equals(420));
        expect(probe.deferredBeforeShow, isTrue);
        expect(probe.hasClipChildrenStyle, isTrue);
        expect(probe.classRedrawStripped, isTrue);
        expect(probe.clientHeightRestored, lessThan(probe.windowHeightHidden));
      },
    );

    test(
      'resolveWin32EraseBkgndAction suppresses WHITE_BRUSH before show and skips FillRect on visible FLUTTERVIEW during resize',
      () {
        // Normal style without custom brush -> delegate to DefSubclassProc
        final normalPass = resolveWin32EraseBkgndAction(
          titleBarStyle: TitleBarStyle.normal,
          hasCustomBrush: false,
          isWindowVisible: true,
          isChildView: true,
        );
        expect(normalPass.intercept, isFalse);
        expect(normalPass.fillWithBrush, isFalse);

        // Pre-Frame-#1 hidden window -> fill dark fallback brush (no white flash)
        final preShowChild = resolveWin32EraseBkgndAction(
          titleBarStyle: TitleBarStyle.hidden,
          hasCustomBrush: false,
          isWindowVisible: false,
          isChildView: true,
        );
        expect(preShowChild.intercept, isTrue);
        expect(preShowChild.fillWithBrush, isTrue);

        // Visible FLUTTERVIEW during live resize -> intercept (return 1) WITHOUT FillRect!
        final liveResizeChild = resolveWin32EraseBkgndAction(
          titleBarStyle: TitleBarStyle.hidden,
          hasCustomBrush: true,
          isWindowVisible: true,
          isChildView: true,
        );
        expect(liveResizeChild.intercept, isTrue);
        expect(liveResizeChild.fillWithBrush, isFalse);

        // Visible parent frame with transparent bg -> intercept WITHOUT FillRect
        final liveResizeTopTransparent = resolveWin32EraseBkgndAction(
          titleBarStyle: TitleBarStyle.hidden,
          hasCustomBrush: false,
          isWindowVisible: true,
          isChildView: false,
        );
        expect(liveResizeTopTransparent.intercept, isTrue);
        expect(liveResizeTopTransparent.fillWithBrush, isFalse);
      },
    );
  });
}
