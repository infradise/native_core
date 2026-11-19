import 'dart:ffi' as ffi;

import '../../diagnostics.dart';
import '../../display_manager.dart';
import '../../models.dart';
import '../window_adapter.dart';
import 'windows_win32_bindings.dart';

/// Queries connected Win32 physical monitors (`EnumDisplayMonitors` +
/// `GetMonitorInfoW` + `GetDpiForMonitor`) with primary-monitor-first ordering.
class WindowsDisplayAdapter implements DisplayPlatformAdapter {
  /// Creates a [WindowsDisplayAdapter].
  const WindowsDisplayAdapter();

  static final List<({Display display, bool isPrimary})> _collected =
      <({Display display, bool isPrimary})>[];

  static int _onMonitorEnum(
    ffi.Pointer<ffi.Void> hMonitor,
    ffi.Pointer<ffi.Void> hdcMonitor,
    ffi.Pointer<Win32Rect> lprcMonitor,
    int dwData,
  ) {
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null || hMonitor == ffi.nullptr) return 1;

    final mi = win32.scratchMonitorInfo;
    mi.ref.cbSize = ffi.sizeOf<Win32MonitorInfo>();
    if (win32.getMonitorInfoW(hMonitor, mi) == 0) return 1;

    final m = mi.ref.rcMonitor;
    final w = mi.ref.rcWork;
    final width = (m.right - m.left).toDouble();
    final height = (m.bottom - m.top).toDouble();
    if (width <= 0 || height <= 0) return 1;

    final workW = (w.right - w.left).toDouble();
    final workH = (w.bottom - w.top).toDouble();

    var scale = 1.0;
    final dpiForMonitor = win32.getDpiForMonitor;
    if (dpiForMonitor != null) {
      final dpiPair = win32.scratchUint32Pair;
      dpiPair[0] = 96;
      dpiPair[1] = 96;
      // MDT_EFFECTIVE_DPI == 0, S_OK == 0
      if (dpiForMonitor(hMonitor, 0, dpiPair, dpiPair + 1) == 0 &&
          dpiPair[0] > 0) {
        scale = dpiPair[0] / 96.0;
      }
    }

    final isPrimary = (mi.ref.dwFlags & kMonitorInfoPrimary) != 0;
    _collected.add((
      display: Display(
        id: _collected.length,
        bounds: NativeRect(m.left.toDouble(), m.top.toDouble(), width, height),
        workArea:
            workW > 0 && workH > 0
                ? NativeRect(w.left.toDouble(), w.top.toDouble(), workW, workH)
                : NativeRect(
                  m.left.toDouble(),
                  m.top.toDouble(),
                  width,
                  height,
                ),
        scaleFactor: scale,
      ),
      isPrimary: isPrimary,
    ));
    return 1;
  }

  @override
  List<Display> getAll() {
    final win32 = WindowsWin32Bindings.instance;
    if (win32 == null) return const <Display>[];

    final enumCallable =
        ffi.NativeCallable<Win32MonitorEnumProcNative>.isolateLocal(
          _onMonitorEnum,
          exceptionalReturn: 0,
        );
    try {
      _collected.clear();
      win32.enumDisplayMonitors(
        ffi.nullptr,
        ffi.nullptr,
        enumCallable.nativeFunction,
        0,
      );
      if (_collected.isNotEmpty) {
        final ordered = <Display>[];
        for (final entry in _collected) {
          if (entry.isPrimary) {
            ordered.add(
              Display(
                id: 0,
                bounds: entry.display.bounds,
                workArea: entry.display.workArea,
                scaleFactor: entry.display.scaleFactor,
              ),
            );
          }
        }
        for (final entry in _collected) {
          if (!entry.isPrimary) {
            ordered.add(
              Display(
                id: ordered.length,
                bounds: entry.display.bounds,
                workArea: entry.display.workArea,
                scaleFactor: entry.display.scaleFactor,
              ),
            );
          }
        }
        _collected.clear();
        return ordered;
      }
    } catch (error, stackTrace) {
      _collected.clear();
      NativeCoreDiagnostics.report(
        'WindowsDisplayAdapter.enumDisplayMonitors',
        error,
        stackTrace,
      );
    } finally {
      enumCallable.close();
    }

    return _queryMetricsFallback(win32);
  }

  List<Display> _queryMetricsFallback(WindowsWin32Bindings win32) {
    try {
      final primaryWidth = win32.getSystemMetrics(kSmCxScreen).toDouble();
      final primaryHeight = win32.getSystemMetrics(kSmCyScreen).toDouble();
      if (primaryWidth <= 0 || primaryHeight <= 0) return const <Display>[];

      final rectPtr = win32.scratchRect;
      var primaryWorkArea = NativeRect(0, 0, primaryWidth, primaryHeight);
      if (win32.systemParametersInfoW(kSpiGetWorkArea, 0, rectPtr, 0) != 0) {
        final w = (rectPtr.ref.right - rectPtr.ref.left).toDouble();
        final h = (rectPtr.ref.bottom - rectPtr.ref.top).toDouble();
        if (w > 0 && h > 0) {
          primaryWorkArea = NativeRect(
            rectPtr.ref.left.toDouble(),
            rectPtr.ref.top.toDouble(),
            w,
            h,
          );
        }
      }

      final displays = <Display>[
        Display(
          id: 0,
          bounds: NativeRect(0, 0, primaryWidth, primaryHeight),
          workArea: primaryWorkArea,
        ),
      ];

      final vx = win32.getSystemMetrics(kSmXVirtualScreen).toDouble();
      final vy = win32.getSystemMetrics(kSmYVirtualScreen).toDouble();
      final vw = win32.getSystemMetrics(kSmCxVirtualScreen).toDouble();
      final vh = win32.getSystemMetrics(kSmCyVirtualScreen).toDouble();
      if (vw > primaryWidth || vh > primaryHeight || vx != 0 || vy != 0) {
        final virtualRect = NativeRect(vx, vy, vw, vh);
        displays.add(
          Display(id: 1, bounds: virtualRect, workArea: virtualRect),
        );
      }
      return displays;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsDisplayAdapter.metricsFallback',
        error,
        stackTrace,
      );
      return const <Display>[];
    }
  }
}
