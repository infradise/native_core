import 'dart:ffi' as ffi;

import '../models.dart';
import 'window_adapter.dart';

/// Pure in-memory [WindowPlatformAdapter] backing `Window.fakeForTesting` in
/// unit and widget tests without touching OS FFI libraries.
class InMemoryWindowAdapter implements WindowPlatformAdapter {
  /// Creates an [InMemoryWindowAdapter] seeded with the specified state.
  InMemoryWindowAdapter({
    bool isMaximized = false,
    bool isMinimized = false,
    bool isFullScreen = false,
    bool isVisible = true,
    bool isFocused = true,
    NativeRect bounds = const NativeRect(0, 0, 1280, 850),
  }) : _isMaximized = isMaximized,
       _isMinimized = isMinimized,
       _isFullScreen = isFullScreen,
       _isVisible = isVisible,
       _isFocused = isFocused,
       _bounds = bounds;

  TitleBarStyle _titleBarStyle = TitleBarStyle.normal;
  bool _isWindowControlButtonsVisible = true;
  NativeColor _backgroundColor = const NativeColor(0x00000000);
  bool _isFullScreen;
  bool _isMaximized;
  bool _isMinimized;
  bool _isVisible;
  bool _isFocused;
  NativeSize _minimumSize = const NativeSize(500, 300);
  bool _isVisibleInTaskbar = true;
  String _title = '';
  NativeRect _bounds;

  @override
  ffi.Pointer<ffi.Void> get nativeHandle => ffi.nullptr;

  @override
  bool get isNative => false;

  @override
  void attach(WindowAdapterEventSink sink) {}

  @override
  TitleBarStyle get titleBarStyle => _titleBarStyle;

  @override
  set titleBarStyle(TitleBarStyle style) {
    _titleBarStyle = style;
  }

  @override
  bool get isWindowControlButtonsVisible => _isWindowControlButtonsVisible;

  @override
  set isWindowControlButtonsVisible(bool visible) {
    _isWindowControlButtonsVisible = visible;
  }

  @override
  NativeColor get backgroundColor => _backgroundColor;

  @override
  set backgroundColor(NativeColor color) {
    _backgroundColor = color;
  }

  @override
  bool get isFullScreen => _isFullScreen;

  @override
  set isFullScreen(bool value) {
    _isFullScreen = value;
  }

  @override
  bool get isMaximized => _isMaximized;

  @override
  bool get isMinimized => _isMinimized;

  @override
  bool get isVisible => _isVisible;

  @override
  bool get isFocused => _isFocused;

  @override
  NativeSize get minimumSize => _minimumSize;

  @override
  set minimumSize(NativeSize size) {
    _minimumSize = size;
  }

  @override
  bool get isVisibleInTaskbar => _isVisibleInTaskbar;

  @override
  set isVisibleInTaskbar(bool visible) {
    _isVisibleInTaskbar = visible;
  }

  @override
  String get title => _title;

  @override
  set title(String value) {
    _title = value;
  }

  @override
  NativeRect get bounds => _bounds;

  @override
  set bounds(NativeRect rect) {
    _bounds = rect;
  }

  @override
  void setSize(NativeSize size, {required bool animate}) {
    _bounds = NativeRect(_bounds.left, _bounds.top, size.width, size.height);
  }

  @override
  void maximize() {
    _isMaximized = true;
    _isMinimized = false;
  }

  @override
  void unmaximize() {
    _isMaximized = false;
  }

  @override
  void minimize() {
    _isMinimized = true;
  }

  @override
  void restore() {
    _isMinimized = false;
    _isMaximized = false;
  }

  @override
  void show() {
    _isVisible = true;
  }

  @override
  void hide() {
    _isVisible = false;
  }

  @override
  void focus() {
    _isFocused = true;
  }

  @override
  void destroyNativeWindow() {
    _isVisible = false;
  }

  @override
  void startDragging() {}

  @override
  bool showSystemMenu(NativeOffset position) => false;

  @override
  void dispose() {}
}
