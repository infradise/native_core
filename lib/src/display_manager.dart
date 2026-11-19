import 'dart:io';

import 'diagnostics.dart';
import 'models.dart';
import 'platform/linux/linux_display_adapter.dart';
import 'platform/macos/macos_display_adapter.dart';
import 'platform/window_adapter.dart';
import 'platform/windows/windows_display_adapter.dart';

/// Information about a connected physical or virtual desktop display.
class Display {
  /// Creates a [Display] descriptor.
  const Display({
    required this.id,
    required this.bounds,
    required this.workArea,
    this.scaleFactor = 1.0,
  });

  /// Display index (`0` denotes the primary display).
  final int id;

  /// Full display bounds in top-left desktop coordinates.
  final NativeRect bounds;

  /// Usable work area excluding taskbars, docks, and system panels.
  final NativeRect workArea;

  /// Backing DPI scale factor (`1.0` = 96 DPI / 1x).
  final double scaleFactor;
}

/// Queries connected desktop displays and their usable work areas via OS FFI.
class DisplayManager {
  DisplayManager._() : _adapter = _selectAdapter();

  /// Process-wide singleton [DisplayManager].
  static final DisplayManager instance = DisplayManager._();

  final DisplayPlatformAdapter? _adapter;

  static DisplayPlatformAdapter? _selectAdapter() {
    if (Platform.isLinux) return const LinuxDisplayAdapter();
    if (Platform.isWindows) return const WindowsDisplayAdapter();
    if (Platform.isMacOS) return const MacOSDisplayAdapter();
    return null;
  }

  /// Returns all connected displays, or an empty list in headless environments.
  List<Display> getAll() {
    final adapter = _adapter;
    if (adapter == null) return const <Display>[];
    try {
      return adapter.getAll();
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report('DisplayManager.getAll', error, stackTrace);
      return const <Display>[];
    }
  }
}
