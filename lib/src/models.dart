import 'dart:ui' show Color, Offset, Rect, Size;

/// Visual style of the native desktop window title bar.
enum TitleBarStyle {
  /// Standard OS window frame and native title bar.
  normal,

  /// Custom client-drawn caption bar with native title bar hidden.
  hidden,
}

/// Identifier returned by `Window.addListener` and passed to
/// `Window.removeListener`.
class ListenerId {
  /// Creates a listener identifier wrapping [value].
  const ListenerId(this.value);

  /// Monotonic integer token identifying a registered listener.
  final int value;

  @override
  bool operator ==(Object other) => other is ListenerId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Cancellable request carried by [WindowCloseRequestedEvent].
class EventRequest {
  /// Creates an event request whose cancellation capability is controlled by
  /// [cancellable].
  EventRequest({this.cancellable = true});

  /// Whether calling [cancel] is permitted to veto the underlying OS action.
  final bool cancellable;
  bool _cancelled = false;

  /// Whether [cancel] was invoked on this request.
  bool get isCancelled => _cancelled;

  /// Cancels the native close operation if [cancellable] is `true`.
  bool cancel() {
    if (!cancellable) return false;
    _cancelled = true;
    return true;
  }
}

/// Base class for all desktop window lifecycle and geometry events.
sealed class WindowEvent {
  /// Creates a [WindowEvent].
  const WindowEvent();
}

/// Emitted when a desktop window's outer dimensions change.
class WindowResizedEvent extends WindowEvent {
  /// Creates a [WindowResizedEvent] with the updated [size].
  const WindowResizedEvent([this.size]);

  /// Updated window dimensions, if known.
  final NativeSize? size;
}

/// Emitted when a desktop window's screen origin changes.
class WindowMovedEvent extends WindowEvent {
  /// Creates a [WindowMovedEvent] with the updated [position].
  const WindowMovedEvent([this.position]);

  /// Updated top-left screen coordinates, if known.
  final NativeOffset? position;
}

/// Emitted when a desktop window enters the maximized state.
class WindowMaximizedEvent extends WindowEvent {
  /// Creates a [WindowMaximizedEvent].
  const WindowMaximizedEvent();
}

/// Emitted when a desktop window exits the maximized state.
class WindowUnmaximizedEvent extends WindowEvent {
  /// Creates a [WindowUnmaximizedEvent].
  const WindowUnmaximizedEvent();
}

/// Emitted when a desktop window is minimized (iconified).
class WindowMinimizedEvent extends WindowEvent {
  /// Creates a [WindowMinimizedEvent].
  const WindowMinimizedEvent();
}

/// Emitted when a desktop window is restored from minimized or maximized state.
class WindowRestoredEvent extends WindowEvent {
  /// Creates a [WindowRestoredEvent].
  const WindowRestoredEvent();
}

/// Emitted when a desktop window gains input focus.
class WindowFocusedEvent extends WindowEvent {
  /// Creates a [WindowFocusedEvent].
  const WindowFocusedEvent();
}

/// Emitted when a desktop window loses input focus.
class WindowBlurredEvent extends WindowEvent {
  /// Creates a [WindowBlurredEvent].
  const WindowBlurredEvent();
}

/// Emitted when the user or OS requests closing the desktop window.
///
/// Listeners may call `request.cancel()` synchronously to veto destruction
/// (for example, to hide the window to the system tray or show a confirmation
/// dialog).
class WindowCloseRequestedEvent extends WindowEvent {
  /// Creates a [WindowCloseRequestedEvent] carrying [request].
  const WindowCloseRequestedEvent(this.request);

  /// Synchronous cancellation handle for the close request.
  final EventRequest request;
}

/// Native 2D size value (`width`, `height`).
class NativeSize {
  /// Creates a [NativeSize] with [width] and [height].
  const NativeSize(this.width, this.height);

  /// Horizontal extent in logical or screen coordinates.
  final double width;

  /// Vertical extent in logical or screen coordinates.
  final double height;

  /// Converts this [NativeSize] to a `dart:ui` [Size].
  Size toSize() => Size(width, height);

  @override
  bool operator ==(Object other) =>
      other is NativeSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// Native 2D offset value (`dx`, `dy`).
class NativeOffset {
  /// Creates a [NativeOffset] with [dx] and [dy].
  const NativeOffset(this.dx, this.dy);

  /// Horizontal coordinate from the primary display's left edge.
  final double dx;

  /// Vertical coordinate from the primary display's top edge.
  final double dy;

  /// Converts this [NativeOffset] to a `dart:ui` [Offset].
  Offset toOffset() => Offset(dx, dy);

  @override
  bool operator ==(Object other) =>
      other is NativeOffset && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);
}

/// Native rectangle value (`left`, `top`, `width`, `height`) using a top-left
/// desktop coordinate origin.
class NativeRect {
  /// Creates a [NativeRect] from [left], [top], [width], and [height].
  const NativeRect(this.left, this.top, this.width, this.height);

  /// Left coordinate relative to the primary display's top-left origin.
  final double left;

  /// Top coordinate relative to the primary display's top-left origin.
  final double top;

  /// Horizontal span of the rectangle.
  final double width;

  /// Vertical span of the rectangle.
  final double height;

  /// Converts this [NativeRect] to a `dart:ui` [Rect].
  Rect toRect() => Rect.fromLTWH(left, top, width, height);

  @override
  bool operator ==(Object other) =>
      other is NativeRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// Native ARGB32 color value (`0xAARRGGBB`).
class NativeColor {
  /// Creates a [NativeColor] from a 32-bit `0xAARRGGBB` integer.
  const NativeColor(this.argb);

  /// Packed 32-bit `0xAARRGGBB` channel value.
  final int argb;

  /// Converts this [NativeColor] to a `dart:ui` [Color].
  Color toColor() => Color(argb);

  @override
  bool operator ==(Object other) => other is NativeColor && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;
}

/// Conversion helper from `dart:ui` [Size] to [NativeSize].
extension NativeSizeConversionX on Size {
  /// Converts this [Size] into a [NativeSize].
  NativeSize toNative() => NativeSize(width, height);
}

/// Conversion helper from `dart:ui` [Offset] to [NativeOffset].
extension NativeOffsetConversionX on Offset {
  /// Converts this [Offset] into a [NativeOffset].
  NativeOffset toNative() => NativeOffset(dx, dy);
}

/// Conversion helper from `dart:ui` [Rect] to [NativeRect].
extension NativeRectConversionX on Rect {
  /// Converts this [Rect] into a [NativeRect].
  NativeRect toNative() => NativeRect(left, top, width, height);
}

/// Conversion helper from `dart:ui` [Color] to [NativeColor].
extension NativeColorConversionX on Color {
  /// Converts this [Color] into a [NativeColor].
  NativeColor toNative() => NativeColor(toARGB32());
}
