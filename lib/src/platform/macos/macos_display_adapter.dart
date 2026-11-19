import 'dart:ffi' as ffi;

import '../../diagnostics.dart';
import '../../display_manager.dart';
import '../../models.dart';
import '../window_adapter.dart';
import 'macos_appkit_bindings.dart';

/// Queries connected `NSScreen` displays (with `CoreGraphics` fallback) and
/// normalizes Cocoa bottom-left frames to desktop top-left coordinates.
class MacOSDisplayAdapter implements DisplayPlatformAdapter {
  /// Creates a [MacOSDisplayAdapter].
  const MacOSDisplayAdapter();

  @override
  List<Display> getAll() {
    final fromNsScreen = _queryNSScreens();
    if (fromNsScreen.isNotEmpty) return fromNsScreen;
    return _queryCoreGraphicsFallback();
  }

  List<Display> _queryNSScreens() {
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return const <Display>[];

    try {
      final nsScreenCls = mac.getClass('NSScreen');
      if (nsScreenCls == ffi.nullptr) return const <Display>[];

      final screens = mac.sendId(nsScreenCls, mac.sel('screens'));
      if (screens == ffi.nullptr) return const <Display>[];

      final count = mac.sendUInt(screens, mac.sel('count'));
      if (count <= 0) return const <Display>[];

      final selObjectAtIndex = mac.sel('objectAtIndex:');
      final selFrame = mac.sel('frame');
      final selVisibleFrame = mac.sel('visibleFrame');
      final selScale = mac.sel('backingScaleFactor');

      final primaryScreen = mac.sendIdUInt(screens, selObjectAtIndex, 0);
      if (primaryScreen == ffi.nullptr) return const <Display>[];
      final primaryHeight = mac.sendRect(primaryScreen, selFrame).size.height;
      if (primaryHeight <= 0) return const <Display>[];

      final result = <Display>[];
      for (var i = 0; i < count; i++) {
        final screen = mac.sendIdUInt(screens, selObjectAtIndex, i);
        if (screen == ffi.nullptr) continue;

        final frame = mac.sendRect(screen, selFrame);
        final visible = mac.sendRect(screen, selVisibleFrame);
        if (frame.size.width <= 0 || frame.size.height <= 0) continue;

        final bounds = NativeRect(
          frame.origin.x,
          primaryHeight - (frame.origin.y + frame.size.height),
          frame.size.width,
          frame.size.height,
        );
        final workArea = NativeRect(
          visible.origin.x,
          primaryHeight - (visible.origin.y + visible.size.height),
          visible.size.width > 0 ? visible.size.width : frame.size.width,
          visible.size.height > 0 ? visible.size.height : frame.size.height,
        );
        final scale = mac.sendDouble(screen, selScale);
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
        'MacOSDisplayAdapter.nsScreens',
        error,
        stackTrace,
      );
      return const <Display>[];
    }
  }

  List<Display> _queryCoreGraphicsFallback() {
    try {
      final cg = ffi.DynamicLibrary.open(
        '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
      );
      final mainDisplayId =
          cg.lookupFunction<ffi.Uint32 Function(), int Function()>(
            'CGMainDisplayID',
          )();
      final cgBounds = cg
          .lookupFunction<MacRect Function(ffi.Uint32), MacRect Function(int)>(
            'CGDisplayBounds',
          )(mainDisplayId);
      final width = cgBounds.size.width;
      final height = cgBounds.size.height;
      if (width <= 0 || height <= 0) return const <Display>[];

      final bounds = NativeRect(
        cgBounds.origin.x,
        cgBounds.origin.y,
        width,
        height,
      );
      return <Display>[
        Display(id: mainDisplayId, bounds: bounds, workArea: bounds),
      ];
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSDisplayAdapter.coreGraphics',
        error,
        stackTrace,
      );
      return const <Display>[];
    }
  }
}
