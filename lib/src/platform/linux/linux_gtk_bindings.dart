import 'dart:ffi' as ffi;
import 'dart:io';

import '../../diagnostics.dart';
import '../../ffi/native_memory.dart';

/// GDK button release event type (`GDK_BUTTON_RELEASE == 7`).
const int kGdkButtonRelease = 7;

/// Primary mouse button (`GDK_BUTTON_PRIMARY == 1`).
const int kGdkButtonPrimary = 1;

/// Secondary mouse button (`GDK_BUTTON_SECONDARY == 3`).
const int kGdkButtonSecondary = 3;

/// `GtkWindowType` value for real top-level application windows (`0`), as
/// opposed to `GTK_WINDOW_POPUP` (`1`) tooltips and popup menus.
const int kGtkWindowToplevel = 0;

/// `GdkWindowState` bit flag indicating an iconified (minimized) window
/// (`1 << 1 == 0x02`).
const int kGdkWindowStateIconified = 0x02;

/// Doubly-linked list node (`GList`) returned by GLib/GTK list APIs.
final class GList extends ffi.Struct {
  /// Element payload pointer.
  external ffi.Pointer<ffi.Void> data;

  /// Next node in the list, or `nullptr`.
  external ffi.Pointer<GList> next;

  /// Previous node in the list, or `nullptr`.
  external ffi.Pointer<GList> prev;
}

/// Native `GdkRectangle` ABI layout (`x`, `y`, `width`, `height`).
final class GdkRectangle extends ffi.Struct {
  /// Left offset in GDK display coordinates.
  @ffi.Int32()
  external int x;

  /// Top offset in GDK display coordinates.
  @ffi.Int32()
  external int y;

  /// Horizontal span in GDK display coordinates.
  @ffi.Int32()
  external int width;

  /// Vertical span in GDK display coordinates.
  @ffi.Int32()
  external int height;
}

/// Native `GdkEventButton` ABI layout used to synthesize button-release events
/// after Wayland/GTK native grabs.
final class GdkEventButton extends ffi.Struct {
  /// `GdkEventType` value (e.g. [kGdkButtonRelease]).
  @ffi.Int32()
  external int type;

  /// Target `GdkWindow*`.
  external ffi.Pointer<ffi.Void> window;

  /// Non-zero when synthesized explicitly.
  @ffi.Int8()
  external int sendEvent;

  /// Event timestamp in milliseconds.
  @ffi.Uint32()
  external int time;

  /// Widget-relative X coordinate.
  @ffi.Double()
  external double x;

  /// Widget-relative Y coordinate.
  @ffi.Double()
  external double y;

  /// Optional axis array pointer.
  external ffi.Pointer<ffi.Double> axes;

  /// Modifier state bitmask.
  @ffi.Uint32()
  external int state;

  /// Mouse button number (`1` = primary, `3` = secondary).
  @ffi.Uint32()
  external int button;

  /// Source `GdkDevice*`.
  external ffi.Pointer<ffi.Void> device;

  /// Root-window X coordinate.
  @ffi.Double()
  external double xRoot;

  /// Root-window Y coordinate.
  @ffi.Double()
  external double yRoot;
}

/// One-time cached FFI symbol table for GTK3, GDK3, GObject, GIO, and GLib on
/// Linux.
class LinuxGtkBindings {
  LinuxGtkBindings._({
    required this.gdkDisplayGetDefault,
    required this.gdkDisplayGetNMonitors,
    required this.gdkDisplayGetMonitor,
    required this.gdkMonitorGetGeometry,
    required this.gdkMonitorGetWorkarea,
    required this.gdkMonitorGetScaleFactor,
    required this.gdkDisplayGetDefaultSeat,
    required this.gdkSeatGetPointer,
    required this.gdkDeviceGetPosition,
    required this.gdkWindowGetState,
    required this.gdkWindowShow,
    required this.gdkWindowFocus,
    required this.gdkEventNew,
    required this.gdkEventSetDevice,
    required this.gdkEventGetDevice,
    required this.gdkEventFree,
    required this.gdkX11WindowGetType,
    required this.gdkX11GetServerTime,
    required this.gtkWindowListToplevels,
    required this.gtkWindowGetWindowType,
    required this.gtkWindowGetTitlebar,
    required this.gtkWindowSetDecorated,
    required this.gtkWindowIsActive,
    required this.gtkWindowIsMaximized,
    required this.gtkWindowMaximize,
    required this.gtkWindowUnmaximize,
    required this.gtkWindowIconify,
    required this.gtkWindowDeiconify,
    required this.gtkWindowFullscreen,
    required this.gtkWindowUnfullscreen,
    required this.gtkWindowPresentWithTime,
    required this.gtkWindowResize,
    required this.gtkWindowMove,
    required this.gtkWindowGetPosition,
    required this.gtkWindowGetSize,
    required this.gtkWindowSetTitle,
    required this.gtkWindowSetSkipTaskbarHint,
    required this.gtkWindowBeginMoveDrag,
    required this.gtkGetCurrentEventTime,
    required this.gtkWidgetInDestruction,
    required this.gtkWidgetGetRealized,
    required this.gtkWidgetGetVisible,
    required this.gtkWidgetSetVisible,
    required this.gtkWidgetShow,
    required this.gtkWidgetHide,
    required this.gtkWidgetDestroy,
    required this.gtkWidgetGetWindow,
    required this.gtkWidgetSetSizeRequest,
    required this.gtkWidgetEvent,
    required this.gtkBinGetChild,
    required this.gtkContainerGetType,
    required this.gtkContainerGetChildren,
    required this.gtkEventBoxGetType,
    required this.gTypeCheckInstanceIsA,
    required this.gSignalConnectData,
    required this.gSignalHandlerIsConnected,
    required this.gSignalHandlerDisconnect,
    required this.gListFree,
    required this.gGetMonotonicTime,
    required this.gApplicationGetDefault,
    required this.gApplicationQuit,
    required this.scratchInts,
    required this.scratchRect,
  });

  static LinuxGtkBindings? _instance;
  static bool _attempted = false;

  /// Returns the cached [LinuxGtkBindings] singleton on Linux, or `null` on
  /// other OSes or headless containers without GTK3 libraries.
  static LinuxGtkBindings? get instance {
    if (!Platform.isLinux) return null;
    if (_attempted) return _instance;
    _attempted = true;

    try {
      final gtk = ffi.DynamicLibrary.open('libgtk-3.so.0');
      final gdk = ffi.DynamicLibrary.open('libgdk-3.so.0');
      final gobject = ffi.DynamicLibrary.open('libgobject-2.0.so.0');
      final glib = ffi.DynamicLibrary.open('libglib-2.0.so.0');
      final gio = ffi.DynamicLibrary.open('libgio-2.0.so.0');

      int Function()? x11GetType;
      int Function(ffi.Pointer<ffi.Void>)? x11ServerTime;
      try {
        x11GetType = gdk.lookupFunction<ffi.Size Function(), int Function()>(
          'gdk_x11_window_get_type',
        );
        x11ServerTime = gdk.lookupFunction<
          ffi.Uint32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gdk_x11_get_server_time');
      } catch (error, stackTrace) {
        NativeCoreDiagnostics.report('LinuxGtkBindings.x11', error, stackTrace);
        x11GetType = null;
        x11ServerTime = null;
      }

      final scratchInts =
          NativeMemory.malloc(4 * ffi.sizeOf<ffi.Int32>()).cast<ffi.Int32>();
      final scratchRect =
          NativeMemory.malloc(ffi.sizeOf<GdkRectangle>()).cast<GdkRectangle>();
      if (scratchInts == ffi.nullptr || scratchRect == ffi.nullptr) {
        if (scratchInts != ffi.nullptr) NativeMemory.free(scratchInts.cast());
        if (scratchRect != ffi.nullptr) NativeMemory.free(scratchRect.cast());
        return null;
      }

      return _instance = LinuxGtkBindings._(
        gdkDisplayGetDefault: gdk.lookupFunction<
          ffi.Pointer<ffi.Void> Function(),
          ffi.Pointer<ffi.Void> Function()
        >('gdk_display_get_default'),
        gdkDisplayGetNMonitors: gdk.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gdk_display_get_n_monitors'),
        gdkDisplayGetMonitor: gdk.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Int32),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
        >('gdk_display_get_monitor'),
        gdkMonitorGetGeometry: gdk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<GdkRectangle>),
          void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<GdkRectangle>)
        >('gdk_monitor_get_geometry'),
        gdkMonitorGetWorkarea: gdk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<GdkRectangle>),
          void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<GdkRectangle>)
        >('gdk_monitor_get_workarea'),
        gdkMonitorGetScaleFactor: gdk.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gdk_monitor_get_scale_factor'),
        gdkDisplayGetDefaultSeat: gdk.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
        >('gdk_display_get_default_seat'),
        gdkSeatGetPointer: gdk.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
        >('gdk_seat_get_pointer'),
        gdkDeviceGetPosition: gdk.lookupFunction<
          ffi.Void Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Int32>,
            ffi.Pointer<ffi.Int32>,
          ),
          void Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Int32>,
            ffi.Pointer<ffi.Int32>,
          )
        >('gdk_device_get_position'),
        gdkWindowGetState: gdk.lookupFunction<
          ffi.Uint32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gdk_window_get_state'),
        gdkWindowShow: gdk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('gdk_window_show'),
        gdkWindowFocus: gdk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
          void Function(ffi.Pointer<ffi.Void>, int)
        >('gdk_window_focus'),
        gdkEventNew: gdk.lookupFunction<
          ffi.Pointer<GdkEventButton> Function(ffi.Int32),
          ffi.Pointer<GdkEventButton> Function(int)
        >('gdk_event_new'),
        gdkEventSetDevice: gdk.lookupFunction<
          ffi.Void Function(ffi.Pointer<GdkEventButton>, ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<GdkEventButton>, ffi.Pointer<ffi.Void>)
        >('gdk_event_set_device'),
        gdkEventGetDevice: gdk.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<GdkEventButton>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<GdkEventButton>)
        >('gdk_event_get_device'),
        gdkEventFree: gdk.lookupFunction<
          ffi.Void Function(ffi.Pointer<GdkEventButton>),
          void Function(ffi.Pointer<GdkEventButton>)
        >('gdk_event_free'),
        gdkX11WindowGetType: x11GetType,
        gdkX11GetServerTime: x11ServerTime,
        gtkWindowListToplevels: gtk.lookupFunction<
          ffi.Pointer<GList> Function(),
          ffi.Pointer<GList> Function()
        >('gtk_window_list_toplevels'),
        gtkWindowGetWindowType: gtk.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gtk_window_get_window_type'),
        gtkWindowGetTitlebar: gtk.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
        >('gtk_window_get_titlebar'),
        gtkWindowSetDecorated: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32),
          void Function(ffi.Pointer<ffi.Void>, int)
        >('gtk_window_set_decorated'),
        gtkWindowIsActive: gtk.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gtk_window_is_active'),
        gtkWindowIsMaximized: gtk.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gtk_window_is_maximized'),
        gtkWindowMaximize: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('gtk_window_maximize'),
        gtkWindowUnmaximize: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('gtk_window_unmaximize'),
        gtkWindowIconify: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('gtk_window_iconify'),
        gtkWindowDeiconify: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('gtk_window_deiconify'),
        gtkWindowFullscreen: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('gtk_window_fullscreen'),
        gtkWindowUnfullscreen: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('gtk_window_unfullscreen'),
        gtkWindowPresentWithTime: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
          void Function(ffi.Pointer<ffi.Void>, int)
        >('gtk_window_present_with_time'),
        gtkWindowResize: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32),
          void Function(ffi.Pointer<ffi.Void>, int, int)
        >('gtk_window_resize'),
        gtkWindowMove: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32),
          void Function(ffi.Pointer<ffi.Void>, int, int)
        >('gtk_window_move'),
        gtkWindowGetPosition: gtk.lookupFunction<
          ffi.Void Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Int32>,
            ffi.Pointer<ffi.Int32>,
          ),
          void Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Int32>,
            ffi.Pointer<ffi.Int32>,
          )
        >('gtk_window_get_position'),
        gtkWindowGetSize: gtk.lookupFunction<
          ffi.Void Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Int32>,
            ffi.Pointer<ffi.Int32>,
          ),
          void Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Int32>,
            ffi.Pointer<ffi.Int32>,
          )
        >('gtk_window_get_size'),
        gtkWindowSetTitle: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>),
          void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>)
        >('gtk_window_set_title'),
        gtkWindowSetSkipTaskbarHint: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32),
          void Function(ffi.Pointer<ffi.Void>, int)
        >('gtk_window_set_skip_taskbar_hint'),
        gtkWindowBeginMoveDrag: gtk.lookupFunction<
          ffi.Void Function(
            ffi.Pointer<ffi.Void>,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Uint32,
          ),
          void Function(ffi.Pointer<ffi.Void>, int, int, int, int)
        >('gtk_window_begin_move_drag'),
        gtkGetCurrentEventTime: gtk
            .lookupFunction<ffi.Uint32 Function(), int Function()>(
              'gtk_get_current_event_time',
            ),
        gtkWidgetInDestruction: gtk.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gtk_widget_in_destruction'),
        gtkWidgetGetRealized: gtk.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gtk_widget_get_realized'),
        gtkWidgetGetVisible: gtk.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gtk_widget_get_visible'),
        gtkWidgetSetVisible: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32),
          void Function(ffi.Pointer<ffi.Void>, int)
        >('gtk_widget_set_visible'),
        gtkWidgetShow: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('gtk_widget_show'),
        gtkWidgetHide: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('gtk_widget_hide'),
        gtkWidgetDestroy: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('gtk_widget_destroy'),
        gtkWidgetGetWindow: gtk.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
        >('gtk_widget_get_window'),
        gtkWidgetSetSizeRequest: gtk.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32),
          void Function(ffi.Pointer<ffi.Void>, int, int)
        >('gtk_widget_set_size_request'),
        gtkWidgetEvent: gtk.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<GdkEventButton>,
          ),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<GdkEventButton>)
        >('gtk_widget_event'),
        gtkBinGetChild: gtk.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
        >('gtk_bin_get_child'),
        gtkContainerGetType: gtk
            .lookupFunction<ffi.Size Function(), int Function()>(
              'gtk_container_get_type',
            ),
        gtkContainerGetChildren: gtk.lookupFunction<
          ffi.Pointer<GList> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<GList> Function(ffi.Pointer<ffi.Void>)
        >('gtk_container_get_children'),
        gtkEventBoxGetType: gtk
            .lookupFunction<ffi.Size Function(), int Function()>(
              'gtk_event_box_get_type',
            ),
        gTypeCheckInstanceIsA: gobject.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Size),
          int Function(ffi.Pointer<ffi.Void>, int)
        >('g_type_check_instance_is_a'),
        gSignalConnectData: gobject.lookupFunction<
          ffi.UnsignedLong Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Int32,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            int,
          )
        >('g_signal_connect_data'),
        gSignalHandlerIsConnected: gobject.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.UnsignedLong),
          int Function(ffi.Pointer<ffi.Void>, int)
        >('g_signal_handler_is_connected'),
        gSignalHandlerDisconnect: gobject.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.UnsignedLong),
          void Function(ffi.Pointer<ffi.Void>, int)
        >('g_signal_handler_disconnect'),
        gListFree: glib.lookupFunction<
          ffi.Void Function(ffi.Pointer<GList>),
          void Function(ffi.Pointer<GList>)
        >('g_list_free'),
        gGetMonotonicTime: glib
            .lookupFunction<ffi.Int64 Function(), int Function()>(
              'g_get_monotonic_time',
            ),
        gApplicationGetDefault: gio.lookupFunction<
          ffi.Pointer<ffi.Void> Function(),
          ffi.Pointer<ffi.Void> Function()
        >('g_application_get_default'),
        gApplicationQuit: gio.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('g_application_quit'),
        scratchInts: scratchInts,
        scratchRect: scratchRect,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report('LinuxGtkBindings.load', error, stackTrace);
      return null;
    }
  }

  /// `gdk_display_get_default`.
  final ffi.Pointer<ffi.Void> Function() gdkDisplayGetDefault;

  /// `gdk_display_get_n_monitors`.
  final int Function(ffi.Pointer<ffi.Void>) gdkDisplayGetNMonitors;

  /// `gdk_display_get_monitor`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
  gdkDisplayGetMonitor;

  /// `gdk_monitor_get_geometry`.
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<GdkRectangle>)
  gdkMonitorGetGeometry;

  /// `gdk_monitor_get_workarea`.
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<GdkRectangle>)
  gdkMonitorGetWorkarea;

  /// `gdk_monitor_get_scale_factor`.
  final int Function(ffi.Pointer<ffi.Void>) gdkMonitorGetScaleFactor;

  /// `gdk_display_get_default_seat`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
  gdkDisplayGetDefaultSeat;

  /// `gdk_seat_get_pointer`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>) gdkSeatGetPointer;

  /// `gdk_device_get_position`.
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>,
  )
  gdkDeviceGetPosition;

  /// `gdk_window_get_state`.
  final int Function(ffi.Pointer<ffi.Void>) gdkWindowGetState;

  /// `gdk_window_show`.
  final void Function(ffi.Pointer<ffi.Void>) gdkWindowShow;

  /// `gdk_window_focus`.
  final void Function(ffi.Pointer<ffi.Void>, int) gdkWindowFocus;

  /// `gdk_event_new`.
  final ffi.Pointer<GdkEventButton> Function(int) gdkEventNew;

  /// `gdk_event_set_device`.
  final void Function(ffi.Pointer<GdkEventButton>, ffi.Pointer<ffi.Void>)
  gdkEventSetDevice;

  /// `gdk_event_get_device`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<GdkEventButton>)
  gdkEventGetDevice;

  /// `gdk_event_free`.
  final void Function(ffi.Pointer<GdkEventButton>) gdkEventFree;

  /// Optional `gdk_x11_window_get_type` (`null` on X11-less builds).
  final int Function()? gdkX11WindowGetType;

  /// Optional `gdk_x11_get_server_time` (`null` on X11-less builds).
  final int Function(ffi.Pointer<ffi.Void>)? gdkX11GetServerTime;

  /// `gtk_window_list_toplevels`.
  final ffi.Pointer<GList> Function() gtkWindowListToplevels;

  /// `gtk_window_get_window_type`.
  final int Function(ffi.Pointer<ffi.Void>) gtkWindowGetWindowType;

  /// `gtk_window_get_titlebar`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
  gtkWindowGetTitlebar;

  /// `gtk_window_set_decorated`.
  final void Function(ffi.Pointer<ffi.Void>, int) gtkWindowSetDecorated;

  /// `gtk_window_is_active`.
  final int Function(ffi.Pointer<ffi.Void>) gtkWindowIsActive;

  /// `gtk_window_is_maximized`.
  final int Function(ffi.Pointer<ffi.Void>) gtkWindowIsMaximized;

  /// `gtk_window_maximize`.
  final void Function(ffi.Pointer<ffi.Void>) gtkWindowMaximize;

  /// `gtk_window_unmaximize`.
  final void Function(ffi.Pointer<ffi.Void>) gtkWindowUnmaximize;

  /// `gtk_window_iconify`.
  final void Function(ffi.Pointer<ffi.Void>) gtkWindowIconify;

  /// `gtk_window_deiconify`.
  final void Function(ffi.Pointer<ffi.Void>) gtkWindowDeiconify;

  /// `gtk_window_fullscreen`.
  final void Function(ffi.Pointer<ffi.Void>) gtkWindowFullscreen;

  /// `gtk_window_unfullscreen`.
  final void Function(ffi.Pointer<ffi.Void>) gtkWindowUnfullscreen;

  /// `gtk_window_present_with_time`.
  final void Function(ffi.Pointer<ffi.Void>, int) gtkWindowPresentWithTime;

  /// `gtk_window_resize`.
  final void Function(ffi.Pointer<ffi.Void>, int, int) gtkWindowResize;

  /// `gtk_window_move`.
  final void Function(ffi.Pointer<ffi.Void>, int, int) gtkWindowMove;

  /// `gtk_window_get_position`.
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>,
  )
  gtkWindowGetPosition;

  /// `gtk_window_get_size`.
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>,
  )
  gtkWindowGetSize;

  /// `gtk_window_set_title`.
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>)
  gtkWindowSetTitle;

  /// `gtk_window_set_skip_taskbar_hint`.
  final void Function(ffi.Pointer<ffi.Void>, int) gtkWindowSetSkipTaskbarHint;

  /// `gtk_window_begin_move_drag`.
  final void Function(ffi.Pointer<ffi.Void>, int, int, int, int)
  gtkWindowBeginMoveDrag;

  /// `gtk_get_current_event_time`.
  final int Function() gtkGetCurrentEventTime;

  /// `gtk_widget_in_destruction`.
  final int Function(ffi.Pointer<ffi.Void>) gtkWidgetInDestruction;

  /// `gtk_widget_get_realized`.
  final int Function(ffi.Pointer<ffi.Void>) gtkWidgetGetRealized;

  /// `gtk_widget_get_visible`.
  final int Function(ffi.Pointer<ffi.Void>) gtkWidgetGetVisible;

  /// `gtk_widget_set_visible`.
  final void Function(ffi.Pointer<ffi.Void>, int) gtkWidgetSetVisible;

  /// `gtk_widget_show`.
  final void Function(ffi.Pointer<ffi.Void>) gtkWidgetShow;

  /// `gtk_widget_hide`.
  final void Function(ffi.Pointer<ffi.Void>) gtkWidgetHide;

  /// `gtk_widget_destroy`.
  final void Function(ffi.Pointer<ffi.Void>) gtkWidgetDestroy;

  /// `gtk_widget_get_window`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
  gtkWidgetGetWindow;

  /// `gtk_widget_set_size_request`.
  final void Function(ffi.Pointer<ffi.Void>, int, int) gtkWidgetSetSizeRequest;

  /// `gtk_widget_event`.
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<GdkEventButton>)
  gtkWidgetEvent;

  /// `gtk_bin_get_child`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>) gtkBinGetChild;

  /// `gtk_container_get_type`.
  final int Function() gtkContainerGetType;

  /// `gtk_container_get_children`.
  final ffi.Pointer<GList> Function(ffi.Pointer<ffi.Void>)
  gtkContainerGetChildren;

  /// `gtk_event_box_get_type`.
  final int Function() gtkEventBoxGetType;

  /// `g_type_check_instance_is_a`.
  final int Function(ffi.Pointer<ffi.Void>, int) gTypeCheckInstanceIsA;

  /// `g_signal_connect_data`.
  final int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    int,
  )
  gSignalConnectData;

  /// `g_signal_handler_is_connected`.
  final int Function(ffi.Pointer<ffi.Void>, int) gSignalHandlerIsConnected;

  /// `g_signal_handler_disconnect`.
  final void Function(ffi.Pointer<ffi.Void>, int) gSignalHandlerDisconnect;

  /// `g_list_free`.
  final void Function(ffi.Pointer<GList>) gListFree;

  /// `g_get_monotonic_time`.
  final int Function() gGetMonotonicTime;

  /// `g_application_get_default`.
  final ffi.Pointer<ffi.Void> Function() gApplicationGetDefault;

  /// `g_application_quit`.
  final void Function(ffi.Pointer<ffi.Void>) gApplicationQuit;

  /// Reusable 4-element `Int32` scratch buffer on the main UI thread.
  final ffi.Pointer<ffi.Int32> scratchInts;

  /// Reusable `GdkRectangle` scratch buffer on the main UI thread.
  final ffi.Pointer<GdkRectangle> scratchRect;
}
