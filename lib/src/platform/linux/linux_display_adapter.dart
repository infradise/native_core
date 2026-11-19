import 'dart:ffi' as ffi;

import '../../diagnostics.dart';
import '../../display_manager.dart';
import '../../models.dart';
import '../window_adapter.dart';
import 'linux_gtk_bindings.dart';

/// Queries connected GDK3 monitors and usable desktop work areas on Linux.
class LinuxDisplayAdapter implements DisplayPlatformAdapter {
  /// Creates a [LinuxDisplayAdapter].
  const LinuxDisplayAdapter();

  @override
  List<Display> getAll() {
    final gtk = LinuxGtkBindings.instance;
    if (gtk == null) return const <Display>[];

    try {
      final display = gtk.gdkDisplayGetDefault();
      if (display == ffi.nullptr) return const <Display>[];

      final count = gtk.gdkDisplayGetNMonitors(display);
      if (count <= 0) return const <Display>[];

      final rectPtr = gtk.scratchRect;
      final result = <Display>[];
      for (var i = 0; i < count; i++) {
        final monitor = gtk.gdkDisplayGetMonitor(display, i);
        if (monitor == ffi.nullptr) continue;

        gtk.gdkMonitorGetGeometry(monitor, rectPtr);
        final bounds = NativeRect(
          rectPtr.ref.x.toDouble(),
          rectPtr.ref.y.toDouble(),
          rectPtr.ref.width.toDouble(),
          rectPtr.ref.height.toDouble(),
        );

        gtk.gdkMonitorGetWorkarea(monitor, rectPtr);
        final workArea = NativeRect(
          rectPtr.ref.x.toDouble(),
          rectPtr.ref.y.toDouble(),
          rectPtr.ref.width.toDouble(),
          rectPtr.ref.height.toDouble(),
        );

        final scale = gtk.gdkMonitorGetScaleFactor(monitor).toDouble();
        result.add(
          Display(
            id: i,
            bounds: bounds,
            workArea: workArea,
            scaleFactor: scale > 0 ? scale : 1.0,
          ),
        );
      }
      return result;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'LinuxDisplayAdapter.getAll',
        error,
        stackTrace,
      );
      return const <Display>[];
    }
  }
}
