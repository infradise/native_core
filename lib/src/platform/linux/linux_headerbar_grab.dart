import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:ui' show Offset;

import '../../diagnostics.dart';
import '../../models.dart';
import '../../window.dart';
import 'linux_gtk_bindings.dart';

ffi.Pointer<ffi.Void> _resolveGtkWindow(LinuxGtkBindings gtk, Window window) {
  final handle = window.nativeObject;
  if (handle != ffi.nullptr) return handle;

  final toplevels = gtk.gtkWindowListToplevels();
  if (toplevels == ffi.nullptr) return ffi.nullptr;
  try {
    var cursor = toplevels;
    while (cursor != ffi.nullptr) {
      final candidate = cursor.ref.data;
      if (candidate != ffi.nullptr &&
          gtk.gtkWindowGetWindowType(candidate) == kGtkWindowToplevel) {
        return candidate;
      }
      cursor = cursor.ref.next;
    }
    return ffi.nullptr;
  } finally {
    gtk.gListFree(toplevels);
  }
}

ffi.Pointer<ffi.Void> _findFlutterEventBox(
  LinuxGtkBindings gtk,
  ffi.Pointer<ffi.Void> widget,
) {
  if (widget == ffi.nullptr) return ffi.nullptr;

  final eventBoxType = gtk.gtkEventBoxGetType();
  if (gtk.gTypeCheckInstanceIsA(widget, eventBoxType) != 0) {
    return widget;
  }

  final containerType = gtk.gtkContainerGetType();
  if (gtk.gTypeCheckInstanceIsA(widget, containerType) == 0) {
    return ffi.nullptr;
  }

  final children = gtk.gtkContainerGetChildren(widget);
  if (children == ffi.nullptr) return ffi.nullptr;
  try {
    var cursor = children;
    while (cursor != ffi.nullptr) {
      final found = _findFlutterEventBox(gtk, cursor.ref.data);
      if (found != ffi.nullptr) return found;
      cursor = cursor.ref.next;
    }
    return ffi.nullptr;
  } finally {
    gtk.gListFree(children);
  }
}

/// Directly hides the native `GtkHeaderBar` (or server-side decorations) on
/// Linux without adding the 132px CSD shadow gutter that clips right/bottom
/// Wayland input regions.
bool hideLinuxNativeTitleBar(Window window) {
  if (!Platform.isLinux) return false;
  final gtk = LinuxGtkBindings.instance;
  if (gtk == null) return false;

  try {
    final gtkWindow = _resolveGtkWindow(gtk, window);
    if (gtkWindow == ffi.nullptr) return false;

    final titlebar = gtk.gtkWindowGetTitlebar(gtkWindow);
    if (titlebar != ffi.nullptr) {
      gtk.gtkWidgetSetVisible(titlebar, 0);
    } else {
      gtk.gtkWindowSetDecorated(gtkWindow, 0);
    }
    return true;
  } catch (error, stackTrace) {
    NativeCoreDiagnostics.report('hideLinuxNativeTitleBar', error, stackTrace);
    return false;
  }
}

/// Synthesizes a `GDK_BUTTON_RELEASE` event on the Flutter `GtkEventBox` after
/// a native window drag or system menu grab consumes the physical release
/// event on Linux GTK3/Wayland.
void releaseLinuxMouseButtonAfterGrab(
  Window window, {
  int button = kGdkButtonPrimary,
}) {
  if (!Platform.isLinux) return;
  final gtk = LinuxGtkBindings.instance;
  if (gtk == null) return;

  try {
    final gtkWindow = _resolveGtkWindow(gtk, window);
    if (gtkWindow == ffi.nullptr) return;

    final child = gtk.gtkBinGetChild(gtkWindow);
    final eventBox = _findFlutterEventBox(gtk, child);
    if (eventBox == ffi.nullptr) return;

    final event = gtk.gdkEventNew(kGdkButtonRelease);
    if (event == ffi.nullptr) return;
    try {
      event.ref
        ..type = kGdkButtonRelease
        ..button = button
        ..time = (gtk.gGetMonotonicTime() ~/ 1000) & 0xFFFFFFFF
        ..x = 0.0
        ..y = 0.0;
      gtk.gtkWidgetEvent(eventBox, event);
    } finally {
      gtk.gdkEventFree(event);
    }
  } catch (error, stackTrace) {
    NativeCoreDiagnostics.report(
      'releaseLinuxMouseButtonAfterGrab',
      error,
      stackTrace,
    );
  }
}

/// Starts a native window drag and schedules a button-release synthesis on
/// Linux so `FlPointerManager` does not remain stuck in the pressed state.
void startPlatformWindowDragging(Window window) {
  window.startDragging();
  if (Platform.isLinux) {
    Timer.run(() => releaseLinuxMouseButtonAfterGrab(window));
  }
}

/// Displays the native window system menu at [globalPosition] and clears the
/// secondary mouse button grab state on Linux.
void showPlatformWindowSystemMenu(Window window, Offset globalPosition) {
  final accepted = window.showSystemMenu(globalPosition.toNative());
  if (Platform.isLinux && accepted) {
    Timer.run(
      () =>
          releaseLinuxMouseButtonAfterGrab(window, button: kGdkButtonSecondary),
    );
  }
}
