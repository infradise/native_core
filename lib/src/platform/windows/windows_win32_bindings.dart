import 'dart:ffi' as ffi;
import 'dart:io';

import '../../diagnostics.dart';
import '../../ffi/native_memory.dart';

/// `WM_CREATE` (`0x0001`).
const int kWmCreate = 0x0001;

/// `WM_DESTROY` (`0x0002`).
const int kWmDestroy = 0x0002;

/// `WM_SIZE` (`0x0005`).
const int kWmSize = 0x0005;

/// `WM_ERASEBKGND` (`0x0014`).
const int kWmEraseBkgnd = 0x0014;

/// `WM_GETMINMAXINFO` (`0x0024`).
const int kWmGetMinMaxInfo = 0x0024;

/// `WM_WINDOWPOSCHANGING` (`0x0046`).
const int kWmWindowPosChanging = 0x0046;

/// `WM_NCCALCSIZE` (`0x0083`).
const int kWmNcCalcSize = 0x0083;

/// `WM_NCHITTEST` (`0x0084`).
const int kWmNcHitTest = 0x0084;

/// `WM_NCLBUTTONDOWN` (`0x00A1`).
const int kWmNcLButtonDown = 0x00A1;

/// `WM_SYSCOMMAND` (`0x0112`).
const int kWmSysCommand = 0x0112;

/// `WM_PARENTNOTIFY` (`0x0210`).
const int kWmParentNotify = 0x0210;

/// Private deferred initial-show message (`WM_APP + 0x4E57`).
const int kWmApplyDeferredWin32Show = 0x8000 + 0x4E57;

/// `SW_HIDE` (`0`).
const int kSwHide = 0;

/// `SW_SHOWMAXIMIZED` (`3`).
const int kSwShowMaximized = 3;

/// `SW_SHOW` (`5`).
const int kSwShow = 5;

/// `SW_MINIMIZE` (`6`).
const int kSwMinimize = 6;

/// `SW_RESTORE` (`9`).
const int kSwRestore = 9;

/// `SWP_NOSIZE` (`0x0001`).
const int kSwpNoSize = 0x0001;

/// `SWP_NOMOVE` (`0x0002`).
const int kSwpNoMove = 0x0002;

/// `SWP_NOZORDER` (`0x0004`).
const int kSwpNoZOrder = 0x0004;

/// `SWP_NOACTIVATE` (`0x0010`).
const int kSwpNoActivate = 0x0010;

/// `SWP_FRAMECHANGED` (`0x0020`).
const int kSwpFrameChanged = 0x0020;

/// `SWP_SHOWWINDOW` (`0x0040`).
const int kSwpShowWindow = 0x0040;

/// `HTTRANSPARENT` (`-1`).
const int kHtTransparent = -1;

/// `HTNOWHERE` (`0`).
const int kHtNowhere = 0;

/// `HTCAPTION` (`2`).
const int kHtCaption = 2;

/// `HTLEFT` (`10`).
const int kHtLeft = 10;

/// `HTRIGHT` (`11`).
const int kHtRight = 11;

/// `HTTOP` (`12`).
const int kHtTop = 12;

/// `HTTOPLEFT` (`13`).
const int kHtTopLeft = 13;

/// `HTTOPRIGHT` (`14`).
const int kHtTopRight = 14;

/// `HTBOTTOM` (`15`).
const int kHtBottom = 15;

/// `HTBOTTOMLEFT` (`16`).
const int kHtBottomLeft = 16;

/// `HTBOTTOMRIGHT` (`17`).
const int kHtBottomRight = 17;

/// `GWL_STYLE` (`-16`).
const int kGwlStyle = -16;

/// `GWL_EXSTYLE` (`-20`).
const int kGwlExStyle = -20;

/// `GCLP_HBRBACKGROUND` (`-10`).
const int kGclpHbrBackground = -10;

/// `GCL_STYLE` (`-26`).
const int kGclStyle = -26;

/// `CS_VREDRAW` (`0x0001`).
const int kCsVRedraw = 0x0001;

/// `CS_HREDRAW` (`0x0002`).
const int kCsHRedraw = 0x0002;

/// `HWND_TOPMOST` (`(HWND)-1`).
const int kHwndTopMost = -1;

/// `HWND_NOTOPMOST` (`(HWND)-2`).
const int kHwndNoTopMost = -2;

/// `WS_EX_TOPMOST` (`0x00000008`).
const int kWsExTopMost = 0x00000008;

/// `WS_EX_TOOLWINDOW` (`0x00000080`).
const int kWsExToolWindow = 0x00000080;

/// `WS_EX_APPWINDOW` (`0x00040000`).
const int kWsExAppWindow = 0x00040000;

/// `WS_CAPTION` (`0x00C00000`).
const int kWsCaption = 0x00C00000;

/// `WS_THICKFRAME` (`0x00040000`).
const int kWsThickFrame = 0x00040000;

/// `WS_MINIMIZEBOX` (`0x00020000`).
const int kWsMinimizeBox = 0x00020000;

/// `WS_MAXIMIZEBOX` (`0x00010000`).
const int kWsMaximizeBox = 0x00010000;

/// `WS_SYSMENU` (`0x00080000`).
const int kWsSysMenu = 0x00080000;

/// `WS_OVERLAPPEDWINDOW` (`0x00CF0000`).
const int kWsOverlappedWindow = 0x00CF0000;

/// `WS_CLIPCHILDREN` (`0x02000000`).
const int kWsClipChildren = 0x02000000;

/// `WS_CLIPSIBLINGS` (`0x04000000`).
const int kWsClipSiblings = 0x04000000;

/// `SM_CXSCREEN` (`0`).
const int kSmCxScreen = 0;

/// `SM_CYSCREEN` (`1`).
const int kSmCyScreen = 1;

/// `SM_CXSIZEFRAME` (`32`).
const int kSmCxSizeFrame = 32;

/// `SM_CYSIZEFRAME` (`33`).
const int kSmCySizeFrame = 33;

/// `SM_XVIRTUALSCREEN` (`76`).
const int kSmXVirtualScreen = 76;

/// `SM_YVIRTUALSCREEN` (`77`).
const int kSmYVirtualScreen = 77;

/// `SM_CXVIRTUALSCREEN` (`78`).
const int kSmCxVirtualScreen = 78;

/// `SM_CYVIRTUALSCREEN` (`79`).
const int kSmCyVirtualScreen = 79;

/// `SM_CXPADDEDBORDER` (`92`).
const int kSmCxPaddedBorder = 92;

/// `SPI_GETWORKAREA` (`0x0030`).
const int kSpiGetWorkArea = 0x0030;

/// `MONITOR_DEFAULTTONEAREST` (`2`).
const int kMonitorDefaultToNearest = 2;

/// `MONITORINFOF_PRIMARY` (`1`).
const int kMonitorInfoPrimary = 1;

/// `GW_CHILD` (`5`).
const int kGwChild = 5;

/// `GA_ROOT` (`2`).
const int kGaRoot = 2;

/// `TPM_RIGHTBUTTON` (`0x0002`).
const int kTpmRightButton = 0x0002;

/// `TPM_RETURNCMD` (`0x0100`).
const int kTpmReturnCmd = 0x0100;

/// `DWMWA_USE_IMMERSIVE_DARK_MODE` (`20`).
const int kDwmwaUseImmersiveDarkMode = 20;

/// `DWMWA_WINDOW_CORNER_PREFERENCE` (`33`).
const int kDwmwaWindowCornerPreference = 33;

/// `DWMWCP_DEFAULT` (`0`).
const int kDwmwcpDefault = 0;

/// `DWMWCP_ROUND` (`2`).
const int kDwmwcpRound = 2;

/// Native Win32 `RECT` ABI layout (`left`, `top`, `right`, `bottom`).
final class Win32Rect extends ffi.Struct {
  /// Left edge in screen or client pixels.
  @ffi.Int32()
  external int left;

  /// Top edge in screen or client pixels.
  @ffi.Int32()
  external int top;

  /// Right edge in screen or client pixels.
  @ffi.Int32()
  external int right;

  /// Bottom edge in screen or client pixels.
  @ffi.Int32()
  external int bottom;
}

/// Native Win32 `POINT` ABI layout (`x`, `y`).
final class Win32Point extends ffi.Struct {
  /// Horizontal coordinate in pixels.
  @ffi.Int32()
  external int x;

  /// Vertical coordinate in pixels.
  @ffi.Int32()
  external int y;
}

/// Native DWM `MARGINS` ABI layout.
final class Win32Margins extends ffi.Struct {
  /// Left frame extension width.
  @ffi.Int32()
  external int cxLeftWidth;

  /// Right frame extension width.
  @ffi.Int32()
  external int cxRightWidth;

  /// Top frame extension height.
  @ffi.Int32()
  external int cyTopHeight;

  /// Bottom frame extension height.
  @ffi.Int32()
  external int cyBottomHeight;
}

/// Native Win32 `MONITORINFO` ABI layout.
final class Win32MonitorInfo extends ffi.Struct {
  /// Byte size of the struct (`sizeof(MONITORINFO)`).
  @ffi.Uint32()
  external int cbSize;

  /// Full display monitor rectangle.
  external Win32Rect rcMonitor;

  /// Usable work-area rectangle excluding taskbars and docked bars.
  external Win32Rect rcWork;

  /// Monitor status flags (`MONITORINFOF_PRIMARY == 1`).
  @ffi.Uint32()
  external int dwFlags;
}

/// Native Win32 `MINMAXINFO` ABI layout (`WM_GETMINMAXINFO`).
final class Win32MinMaxInfo extends ffi.Struct {
  /// Reserved by Win32.
  external Win32Point ptReserved;

  /// Maximized width and height.
  external Win32Point ptMaxSize;

  /// Maximized origin.
  external Win32Point ptMaxPosition;

  /// Minimum interactive resize dimensions.
  external Win32Point ptMinTrackSize;

  /// Maximum interactive resize dimensions.
  external Win32Point ptMaxTrackSize;
}

/// Native Win32 `WINDOWPOS` ABI layout (`WM_WINDOWPOSCHANGING`).
final class Win32WindowPos extends ffi.Struct {
  /// Target `HWND`.
  external ffi.Pointer<ffi.Void> hwnd;

  /// Z-order reference `HWND`.
  external ffi.Pointer<ffi.Void> hwndInsertAfter;

  /// New left coordinate.
  @ffi.Int32()
  external int x;

  /// New top coordinate.
  @ffi.Int32()
  external int y;

  /// New width.
  @ffi.Int32()
  external int cx;

  /// New height.
  @ffi.Int32()
  external int cy;

  /// `SWP_*` bitmask flags.
  @ffi.Uint32()
  external int flags;
}

/// Native `SUBCLASSPROC` function signature (`comctl32.dll`).
typedef Win32SubclassProcNative =
    ffi.IntPtr Function(
      ffi.Pointer<ffi.Void> hwnd,
      ffi.Uint32 msg,
      ffi.UintPtr wParam,
      ffi.IntPtr lParam,
      ffi.UintPtr uIdSubclass,
      ffi.UintPtr dwRefData,
    );

/// Native `MONITORENUMPROC` function signature (`user32.dll`).
typedef Win32MonitorEnumProcNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> hMonitor,
      ffi.Pointer<ffi.Void> hdcMonitor,
      ffi.Pointer<Win32Rect> lprcMonitor,
      ffi.IntPtr dwData,
    );

/// Unified one-time cached Win32, Comctl32, DWM, GDI, and Shcore FFI bindings
/// for Windows.
class WindowsWin32Bindings {
  WindowsWin32Bindings._({
    required this.getCurrentProcessId,
    required this.getCurrentThreadId,
    required this.getModuleHandleW,
    required this.findWindowExW,
    required this.getWindowThreadProcessId,
    required this.isWindow,
    required this.isWindowVisible,
    required this.isZoomed,
    required this.isIconic,
    required this.getWindowRect,
    required this.getClientRect,
    required this.getWindow,
    required this.getAncestor,
    required this.getForegroundWindow,
    required this.setForegroundWindow,
    required this.bringWindowToTop,
    required this.attachThreadInput,
    required this.getFocus,
    required this.setFocus,
    required this.releaseCapture,
    required this.getCursorPos,
    required this.getSystemMenu,
    required this.trackPopupMenu,
    required this.setWindowTextW,
    required this.getDpiForWindow,
    required this.getDpiForMonitor,
    required this.getSystemMetrics,
    required this.getSystemMetricsForDpi,
    required this.systemParametersInfoW,
    required this.monitorFromWindow,
    required this.getMonitorInfoW,
    required this.enumDisplayMonitors,
    required this.getWindowLongPtrW,
    required this.setWindowLongPtrW,
    required this.getClassLongPtrW,
    required this.setClassLongPtrW,
    required this.setWindowPos,
    required this.showWindow,
    required this.destroyWindow,
    required this.createWindowExW,
    required this.sendMessageW,
    required this.postMessageW,
    required this.postQuitMessage,
    required this.fillRect,
    required this.setWindowSubclass,
    required this.removeWindowSubclass,
    required this.defSubclassProc,
    required this.dwmExtendFrameIntoClientArea,
    required this.dwmSetWindowAttribute,
    required this.createSolidBrush,
    required this.deleteObject,
    required this.scratchRect,
    required this.scratchPoint,
    required this.scratchMonitorInfo,
    required this.scratchMargins,
    required this.scratchInt32,
    required this.scratchUint32Pair,
  });

  static WindowsWin32Bindings? _instance;
  static bool _attempted = false;

  /// Returns the cached [WindowsWin32Bindings] singleton on Windows, or `null`
  /// on other OSes.
  static WindowsWin32Bindings? get instance {
    if (!Platform.isWindows) return null;
    if (_attempted) return _instance;
    _attempted = true;

    try {
      final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      final user32 = ffi.DynamicLibrary.open('user32.dll');
      final comctl32 = ffi.DynamicLibrary.open('comctl32.dll');
      final dwmapi = ffi.DynamicLibrary.open('dwmapi.dll');
      final gdi32 = ffi.DynamicLibrary.open('gdi32.dll');

      int Function(ffi.Pointer<ffi.Void>)? dpiForWin;
      try {
        dpiForWin = user32.lookupFunction<
          ffi.Uint32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('GetDpiForWindow');
      } catch (_) {
        dpiForWin = null;
      }

      int Function(
        ffi.Pointer<ffi.Void>,
        int,
        ffi.Pointer<ffi.Uint32>,
        ffi.Pointer<ffi.Uint32>,
      )?
      dpiForMonitor;
      try {
        final shcore = ffi.DynamicLibrary.open('shcore.dll');
        dpiForMonitor = shcore.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Int32,
            ffi.Pointer<ffi.Uint32>,
            ffi.Pointer<ffi.Uint32>,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            int,
            ffi.Pointer<ffi.Uint32>,
            ffi.Pointer<ffi.Uint32>,
          )
        >('GetDpiForMonitor');
      } catch (_) {
        dpiForMonitor = null;
      }

      final getSysMetrics = user32
          .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
            'GetSystemMetrics',
          );

      int Function(int, int)? sysMetricsForDpi;
      try {
        sysMetricsForDpi = user32.lookupFunction<
          ffi.Int32 Function(ffi.Int32, ffi.Uint32),
          int Function(int, int)
        >('GetSystemMetricsForDpi');
      } catch (_) {
        sysMetricsForDpi = null;
      }

      final is64Bit = ffi.sizeOf<ffi.IntPtr>() == 8;
      final getLongName = is64Bit ? 'GetWindowLongPtrW' : 'GetWindowLongW';
      final setLongName = is64Bit ? 'SetWindowLongPtrW' : 'SetWindowLongW';
      final getClassLongName = is64Bit ? 'GetClassLongPtrW' : 'GetClassLongW';
      final setClassLongName = is64Bit ? 'SetClassLongPtrW' : 'SetClassLongW';

      final scratchRect =
          NativeMemory.malloc(ffi.sizeOf<Win32Rect>()).cast<Win32Rect>();
      final scratchPoint =
          NativeMemory.malloc(ffi.sizeOf<Win32Point>()).cast<Win32Point>();
      final scratchMi =
          NativeMemory.malloc(
            ffi.sizeOf<Win32MonitorInfo>(),
          ).cast<Win32MonitorInfo>();
      final scratchMargins =
          NativeMemory.malloc(ffi.sizeOf<Win32Margins>()).cast<Win32Margins>();
      final scratchInt32 =
          NativeMemory.malloc(ffi.sizeOf<ffi.Int32>()).cast<ffi.Int32>();
      final scratchUint32Pair =
          NativeMemory.malloc(2 * ffi.sizeOf<ffi.Uint32>()).cast<ffi.Uint32>();

      if (scratchRect == ffi.nullptr ||
          scratchPoint == ffi.nullptr ||
          scratchMi == ffi.nullptr ||
          scratchMargins == ffi.nullptr ||
          scratchInt32 == ffi.nullptr ||
          scratchUint32Pair == ffi.nullptr) {
        if (scratchRect != ffi.nullptr) NativeMemory.free(scratchRect.cast());
        if (scratchPoint != ffi.nullptr) NativeMemory.free(scratchPoint.cast());
        if (scratchMi != ffi.nullptr) NativeMemory.free(scratchMi.cast());
        if (scratchMargins != ffi.nullptr) {
          NativeMemory.free(scratchMargins.cast());
        }
        if (scratchInt32 != ffi.nullptr) NativeMemory.free(scratchInt32.cast());
        if (scratchUint32Pair != ffi.nullptr) {
          NativeMemory.free(scratchUint32Pair.cast());
        }
        return null;
      }

      return _instance = WindowsWin32Bindings._(
        getCurrentProcessId: kernel32
            .lookupFunction<ffi.Uint32 Function(), int Function()>(
              'GetCurrentProcessId',
            ),
        getCurrentThreadId: kernel32
            .lookupFunction<ffi.Uint32 Function(), int Function()>(
              'GetCurrentThreadId',
            ),
        getModuleHandleW: kernel32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint16>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint16>)
        >('GetModuleHandleW'),
        findWindowExW: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint16>,
            ffi.Pointer<ffi.Uint16>,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint16>,
            ffi.Pointer<ffi.Uint16>,
          )
        >('FindWindowExW'),
        getWindowThreadProcessId: user32.lookupFunction<
          ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint32>),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint32>)
        >('GetWindowThreadProcessId'),
        isWindow: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('IsWindow'),
        isWindowVisible: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('IsWindowVisible'),
        isZoomed: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('IsZoomed'),
        isIconic: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('IsIconic'),
        getWindowRect: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32Rect>),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32Rect>)
        >('GetWindowRect'),
        getClientRect: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32Rect>),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32Rect>)
        >('GetClientRect'),
        getWindow: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
        >('GetWindow'),
        getAncestor: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
        >('GetAncestor'),
        getForegroundWindow: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(),
          ffi.Pointer<ffi.Void> Function()
        >('GetForegroundWindow'),
        setForegroundWindow: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('SetForegroundWindow'),
        bringWindowToTop: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('BringWindowToTop'),
        attachThreadInput: user32.lookupFunction<
          ffi.Int32 Function(ffi.Uint32, ffi.Uint32, ffi.Int32),
          int Function(int, int, int)
        >('AttachThreadInput'),
        getFocus: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(),
          ffi.Pointer<ffi.Void> Function()
        >('GetFocus'),
        setFocus: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
        >('SetFocus'),
        releaseCapture: user32
            .lookupFunction<ffi.Int32 Function(), int Function()>(
              'ReleaseCapture',
            ),
        getCursorPos: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<Win32Point>),
          int Function(ffi.Pointer<Win32Point>)
        >('GetCursorPos'),
        getSystemMenu: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Int32),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
        >('GetSystemMenu'),
        trackPopupMenu: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            int,
            int,
            int,
            int,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          )
        >('TrackPopupMenu'),
        setWindowTextW: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint16>),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint16>)
        >('SetWindowTextW'),
        getDpiForWindow: (hwnd) {
          if (dpiForWin != null) {
            final dpi = dpiForWin(hwnd);
            if (dpi > 0) return dpi;
          }
          return 96;
        },
        getDpiForMonitor: dpiForMonitor,
        getSystemMetrics: getSysMetrics,
        getSystemMetricsForDpi: (index, dpi) {
          if (sysMetricsForDpi != null && dpi > 0) {
            return sysMetricsForDpi(index, dpi);
          }
          return getSysMetrics(index);
        },
        systemParametersInfoW: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Uint32,
            ffi.Uint32,
            ffi.Pointer<Win32Rect>,
            ffi.Uint32,
          ),
          int Function(int, int, ffi.Pointer<Win32Rect>, int)
        >('SystemParametersInfoW'),
        monitorFromWindow: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
        >('MonitorFromWindow'),
        getMonitorInfoW: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<Win32MonitorInfo>,
          ),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32MonitorInfo>)
        >('GetMonitorInfoW'),
        enumDisplayMonitors: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<Win32Rect>,
            ffi.Pointer<ffi.NativeFunction<Win32MonitorEnumProcNative>>,
            ffi.IntPtr,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<Win32Rect>,
            ffi.Pointer<ffi.NativeFunction<Win32MonitorEnumProcNative>>,
            int,
          )
        >('EnumDisplayMonitors'),
        getWindowLongPtrW: user32.lookupFunction<
          ffi.IntPtr Function(ffi.Pointer<ffi.Void>, ffi.Int32),
          int Function(ffi.Pointer<ffi.Void>, int)
        >(getLongName),
        setWindowLongPtrW: user32.lookupFunction<
          ffi.IntPtr Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.IntPtr),
          int Function(ffi.Pointer<ffi.Void>, int, int)
        >(setLongName),
        getClassLongPtrW: user32.lookupFunction<
          ffi.IntPtr Function(ffi.Pointer<ffi.Void>, ffi.Int32),
          int Function(ffi.Pointer<ffi.Void>, int)
        >(getClassLongName),
        setClassLongPtrW: user32.lookupFunction<
          ffi.IntPtr Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.IntPtr),
          int Function(ffi.Pointer<ffi.Void>, int, int)
        >(setClassLongName),
        setWindowPos: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Uint32,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            int,
            int,
            int,
            int,
            int,
          )
        >('SetWindowPos'),
        showWindow: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Int32),
          int Function(ffi.Pointer<ffi.Void>, int)
        >('ShowWindow'),
        destroyWindow: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('DestroyWindow'),
        createWindowExW: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Uint32,
            ffi.Pointer<ffi.Uint16>,
            ffi.Pointer<ffi.Uint16>,
            ffi.Uint32,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          ),
          ffi.Pointer<ffi.Void> Function(
            int,
            ffi.Pointer<ffi.Uint16>,
            ffi.Pointer<ffi.Uint16>,
            int,
            int,
            int,
            int,
            int,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          )
        >('CreateWindowExW'),
        sendMessageW: user32.lookupFunction<
          ffi.IntPtr Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.UintPtr,
            ffi.IntPtr,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, int, int)
        >('SendMessageW'),
        postMessageW: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.UintPtr,
            ffi.IntPtr,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, int, int)
        >('PostMessageW'),
        postQuitMessage: user32
            .lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
              'PostQuitMessage',
            ),
        fillRect: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<Win32Rect>,
            ffi.Pointer<ffi.Void>,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<Win32Rect>,
            ffi.Pointer<ffi.Void>,
          )
        >('FillRect'),
        setWindowSubclass: comctl32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.NativeFunction<Win32SubclassProcNative>>,
            ffi.UintPtr,
            ffi.UintPtr,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.NativeFunction<Win32SubclassProcNative>>,
            int,
            int,
          )
        >('SetWindowSubclass'),
        removeWindowSubclass: comctl32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.NativeFunction<Win32SubclassProcNative>>,
            ffi.UintPtr,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.NativeFunction<Win32SubclassProcNative>>,
            int,
          )
        >('RemoveWindowSubclass'),
        defSubclassProc: comctl32.lookupFunction<
          ffi.IntPtr Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.UintPtr,
            ffi.IntPtr,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, int, int)
        >('DefSubclassProc'),
        dwmExtendFrameIntoClientArea: dwmapi.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32Margins>),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32Margins>)
        >('DwmExtendFrameIntoClientArea'),
        dwmSetWindowAttribute: dwmapi.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>, int)
        >('DwmSetWindowAttribute'),
        createSolidBrush: gdi32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Uint32),
          ffi.Pointer<ffi.Void> Function(int)
        >('CreateSolidBrush'),
        deleteObject: gdi32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('DeleteObject'),
        scratchRect: scratchRect,
        scratchPoint: scratchPoint,
        scratchMonitorInfo: scratchMi,
        scratchMargins: scratchMargins,
        scratchInt32: scratchInt32,
        scratchUint32Pair: scratchUint32Pair,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsWin32Bindings.load',
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// `GetCurrentProcessId`.
  final int Function() getCurrentProcessId;

  /// `GetCurrentThreadId`.
  final int Function() getCurrentThreadId;

  /// `GetModuleHandleW`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint16>)
  getModuleHandleW;

  /// `FindWindowExW`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Uint16>,
    ffi.Pointer<ffi.Uint16>,
  )
  findWindowExW;

  /// `GetWindowThreadProcessId`.
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint32>)
  getWindowThreadProcessId;

  /// `IsWindow`.
  final int Function(ffi.Pointer<ffi.Void>) isWindow;

  /// `IsWindowVisible`.
  final int Function(ffi.Pointer<ffi.Void>) isWindowVisible;

  /// `IsZoomed`.
  final int Function(ffi.Pointer<ffi.Void>) isZoomed;

  /// `IsIconic`.
  final int Function(ffi.Pointer<ffi.Void>) isIconic;

  /// `GetWindowRect`.
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32Rect>)
  getWindowRect;

  /// `GetClientRect`.
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32Rect>)
  getClientRect;

  /// `GetWindow`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int) getWindow;

  /// `GetAncestor`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int) getAncestor;

  /// `GetForegroundWindow`.
  final ffi.Pointer<ffi.Void> Function() getForegroundWindow;

  /// `SetForegroundWindow`.
  final int Function(ffi.Pointer<ffi.Void>) setForegroundWindow;

  /// `BringWindowToTop`.
  final int Function(ffi.Pointer<ffi.Void>) bringWindowToTop;

  /// `AttachThreadInput`.
  final int Function(int, int, int) attachThreadInput;

  /// `GetFocus`.
  final ffi.Pointer<ffi.Void> Function() getFocus;

  /// `SetFocus`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>) setFocus;

  /// `ReleaseCapture`.
  final int Function() releaseCapture;

  /// `GetCursorPos`.
  final int Function(ffi.Pointer<Win32Point>) getCursorPos;

  /// `GetSystemMenu`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
  getSystemMenu;

  /// `TrackPopupMenu`.
  final int Function(
    ffi.Pointer<ffi.Void>,
    int,
    int,
    int,
    int,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  trackPopupMenu;

  /// `SetWindowTextW`.
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint16>)
  setWindowTextW;

  /// `GetDpiForWindow` (returns `96` fallback if unavailable).
  final int Function(ffi.Pointer<ffi.Void>) getDpiForWindow;

  /// Optional `GetDpiForMonitor` (`shcore.dll`).
  final int Function(
    ffi.Pointer<ffi.Void>,
    int,
    ffi.Pointer<ffi.Uint32>,
    ffi.Pointer<ffi.Uint32>,
  )?
  getDpiForMonitor;

  /// `GetSystemMetrics`.
  final int Function(int) getSystemMetrics;

  /// `GetSystemMetricsForDpi` (with `GetSystemMetrics` fallback).
  final int Function(int, int) getSystemMetricsForDpi;

  /// `SystemParametersInfoW`.
  final int Function(int, int, ffi.Pointer<Win32Rect>, int)
  systemParametersInfoW;

  /// `MonitorFromWindow`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
  monitorFromWindow;

  /// `GetMonitorInfoW`.
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32MonitorInfo>)
  getMonitorInfoW;

  /// `EnumDisplayMonitors`.
  final int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Win32Rect>,
    ffi.Pointer<ffi.NativeFunction<Win32MonitorEnumProcNative>>,
    int,
  )
  enumDisplayMonitors;

  /// `GetWindowLongPtrW` / `GetWindowLongW`.
  final int Function(ffi.Pointer<ffi.Void>, int) getWindowLongPtrW;

  /// `SetWindowLongPtrW` / `SetWindowLongW`.
  final int Function(ffi.Pointer<ffi.Void>, int, int) setWindowLongPtrW;

  /// `GetClassLongPtrW` / `GetClassLongW`.
  final int Function(ffi.Pointer<ffi.Void>, int) getClassLongPtrW;

  /// `SetClassLongPtrW` / `SetClassLongW`.
  final int Function(ffi.Pointer<ffi.Void>, int, int) setClassLongPtrW;

  /// `SetWindowPos`.
  final int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    int,
    int,
    int,
    int,
    int,
  )
  setWindowPos;

  /// `ShowWindow`.
  final int Function(ffi.Pointer<ffi.Void>, int) showWindow;

  /// `DestroyWindow`.
  final int Function(ffi.Pointer<ffi.Void>) destroyWindow;

  /// `CreateWindowExW`.
  final ffi.Pointer<ffi.Void> Function(
    int,
    ffi.Pointer<ffi.Uint16>,
    ffi.Pointer<ffi.Uint16>,
    int,
    int,
    int,
    int,
    int,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  createWindowExW;

  /// `SendMessageW`.
  final int Function(ffi.Pointer<ffi.Void>, int, int, int) sendMessageW;

  /// `PostMessageW`.
  final int Function(ffi.Pointer<ffi.Void>, int, int, int) postMessageW;

  /// `PostQuitMessage`.
  final void Function(int) postQuitMessage;

  /// `FillRect`.
  final int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Win32Rect>,
    ffi.Pointer<ffi.Void>,
  )
  fillRect;

  /// `SetWindowSubclass` (`comctl32.dll`).
  final int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.NativeFunction<Win32SubclassProcNative>>,
    int,
    int,
  )
  setWindowSubclass;

  /// `RemoveWindowSubclass` (`comctl32.dll`).
  final int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.NativeFunction<Win32SubclassProcNative>>,
    int,
  )
  removeWindowSubclass;

  /// `DefSubclassProc` (`comctl32.dll`).
  final int Function(ffi.Pointer<ffi.Void>, int, int, int) defSubclassProc;

  /// `DwmExtendFrameIntoClientArea` (`dwmapi.dll`).
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Win32Margins>)
  dwmExtendFrameIntoClientArea;

  /// `DwmSetWindowAttribute` (`dwmapi.dll`).
  final int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>, int)
  dwmSetWindowAttribute;

  /// `CreateSolidBrush` (`gdi32.dll`).
  final ffi.Pointer<ffi.Void> Function(int) createSolidBrush;

  /// `DeleteObject` (`gdi32.dll`).
  final int Function(ffi.Pointer<ffi.Void>) deleteObject;

  /// Reusable `Win32Rect` scratch buffer on the main UI thread.
  final ffi.Pointer<Win32Rect> scratchRect;

  /// Reusable `Win32Point` scratch buffer on the main UI thread.
  final ffi.Pointer<Win32Point> scratchPoint;

  /// Reusable `Win32MonitorInfo` scratch buffer on the main UI thread.
  final ffi.Pointer<Win32MonitorInfo> scratchMonitorInfo;

  /// Reusable `Win32Margins` scratch buffer on the main UI thread.
  final ffi.Pointer<Win32Margins> scratchMargins;

  /// Reusable `Int32` scratch buffer on the main UI thread.
  final ffi.Pointer<ffi.Int32> scratchInt32;

  /// Reusable 2-element `Uint32` scratch buffer on the main UI thread.
  final ffi.Pointer<ffi.Uint32> scratchUint32Pair;

  /// Dark neutral fallback brush (`#111618` -> `COLORREF 0x00181611`) used to
  /// prevent `FLUTTERVIEW`'s stock `WHITE_BRUSH` from flashing `#FFFFFF` before
  /// Frame #1 or during rapid edge resize when custom frameless mode is active.
  late final ffi.Pointer<ffi.Void> darkFallbackBrush = createSolidBrush(
    0x00181611,
  );
}

/// Posts `WM_QUIT` with [exitCode] to the current thread's Win32 message queue.
void postWindowsQuitMessage(int exitCode) {
  final win32 = WindowsWin32Bindings.instance;
  if (win32 == null) return;
  try {
    win32.postQuitMessage(exitCode);
  } catch (error, stackTrace) {
    NativeCoreDiagnostics.report('postWindowsQuitMessage', error, stackTrace);
  }
}
