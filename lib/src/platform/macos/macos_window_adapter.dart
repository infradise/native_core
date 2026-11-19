import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../../diagnostics.dart';
import '../../models.dart';
import '../window_adapter.dart';
import 'macos_appkit_bindings.dart';
import 'macos_window_delegate.dart';

/// Resolves whether `MacOSWindowAdapter.hide()` should switch `NSApplication`
/// from `Regular (0)` to `Accessory (1)` so the Dock running indicator dot
/// disappears while a menu bar `NSStatusItem` remains active (matching macOS
/// menu-bar apps such as Docker Desktop and Rancher Desktop).
bool shouldSwitchMacOSActivationPolicyOnHide({
  required bool hasActiveStatusItem,
  required bool hasOtherVisibleAppWindow,
  required bool isVisibleInTaskbar,
}) {
  return isVisibleInTaskbar && hasActiveStatusItem && !hasOtherVisibleAppWindow;
}

/// Resolves whether `MacOSWindowAdapter.show()` / `focus()` / reopen should
/// switch `NSApplication` back to `Regular (0)` before activating the window so
/// the Dock running indicator dot and application menu bar reappear.
bool shouldRestoreMacOSActivationPolicyOnShow({
  required bool switchedToAccessoryOnHide,
  required bool isVisibleInTaskbar,
  required int currentActivationPolicy,
}) {
  if (switchedToAccessoryOnHide) return true;
  return isVisibleInTaskbar &&
      currentActivationPolicy != kNSApplicationActivationPolicyRegular;
}

bool _isStatusBarWindow(MacOSAppKitBindings mac, ffi.Pointer<ffi.Void> win) {
  if (win == ffi.nullptr) return false;
  return mac.dartClassName(win) == 'NSStatusBarWindow';
}

bool _hasActiveStatusBarItem(
  MacOSAppKitBindings mac,
  ffi.Pointer<ffi.Void> sharedApp,
) {
  if (sharedApp == ffi.nullptr) return false;
  final windows = mac.sendId(sharedApp, mac.sel('windows'));
  if (windows == ffi.nullptr) return false;
  final count = mac.sendUInt(windows, mac.sel('count'));
  final selAt = mac.sel('objectAtIndex:');
  final selVisible = mac.sel('isVisible');
  for (var i = 0; i < count; i++) {
    final win = mac.sendIdUInt(windows, selAt, i);
    if (win == ffi.nullptr) continue;
    if (_isStatusBarWindow(mac, win) && mac.sendBool(win, selVisible)) {
      return true;
    }
  }
  return false;
}

bool _hasOtherVisibleAppWindow(
  MacOSAppKitBindings mac,
  ffi.Pointer<ffi.Void> sharedApp, {
  required ffi.Pointer<ffi.Void> excluding,
}) {
  if (sharedApp == ffi.nullptr) return false;
  final windows = mac.sendId(sharedApp, mac.sel('windows'));
  if (windows == ffi.nullptr) return false;
  final count = mac.sendUInt(windows, mac.sel('count'));
  final selAt = mac.sel('objectAtIndex:');
  final selVisible = mac.sel('isVisible');
  for (var i = 0; i < count; i++) {
    final win = mac.sendIdUInt(windows, selAt, i);
    if (win == ffi.nullptr || win == excluding) continue;
    if (_isStatusBarWindow(mac, win)) continue;
    if (_isCandidateAppWindow(mac, win) && mac.sendBool(win, selVisible)) {
      return true;
    }
  }
  return false;
}

/// Result of [debugRunMacOSStatusItemActivationPolicyProbe].
class MacOSActivationPolicyProbeResult {
  /// Creates a [MacOSActivationPolicyProbeResult].
  const MacOSActivationPolicyProbeResult({
    required this.detectedStatusBarWindowWhileActive,
    required this.switchedToAccessoryPolicy,
    required this.restoredRegularPolicy,
    required this.clearedStatusBarWindowAfterRemove,
  });

  /// Whether a live `NSStatusItem` was detected as a visible
  /// `NSStatusBarWindow` in `[NSApp windows]`.
  final bool detectedStatusBarWindowWhileActive;

  /// Whether `setActivationPolicy:` switched `NSApp` to `Accessory (1)`.
  final bool switchedToAccessoryPolicy;

  /// Whether `setActivationPolicy:` restored `NSApp` to `Regular (0)`.
  final bool restoredRegularPolicy;

  /// Whether removing the `NSStatusItem` cleared active status-bar detection.
  final bool clearedStatusBarWindowAfterRemove;
}

/// Live macOS FFI probe verifying `NSStatusBarWindow` detection and
/// `NSApplication.setActivationPolicy:` transitions on macOS 13 through 27+.
MacOSActivationPolicyProbeResult?
debugRunMacOSStatusItemActivationPolicyProbe() {
  if (!Platform.isMacOS) return null;
  final mac = MacOSAppKitBindings.instance;
  if (mac == null) return null;

  final nsAppCls = mac.getClass('NSApplication');
  final nsStatusBarCls = mac.getClass('NSStatusBar');
  if (nsAppCls == ffi.nullptr || nsStatusBarCls == ffi.nullptr) return null;

  final sharedApp = mac.sendId(nsAppCls, mac.sel('sharedApplication'));
  final systemBar = mac.sendId(nsStatusBarCls, mac.sel('systemStatusBar'));
  if (sharedApp == ffi.nullptr || systemBar == ffi.nullptr) return null;

  final sendIdDouble =
      ffi.DynamicLibrary.open('/usr/lib/libobjc.A.dylib')
          .lookup<ffi.NativeFunction<ffi.Void Function()>>('objc_msgSend')
          .cast<
            ffi.NativeFunction<
              ffi.Pointer<ffi.Void> Function(
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
                ffi.Double,
              )
            >
          >()
          .asFunction<
            ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>,
              double,
            )
          >();

  final previousPolicy = mac.sendInt(sharedApp, mac.sel('activationPolicy'));
  final statusItem = sendIdDouble(
    systemBar,
    mac.sel('statusItemWithLength:'),
    -1.0,
  );
  if (statusItem == ffi.nullptr) return null;

  try {
    final activeBeforeRemove = _hasActiveStatusBarItem(mac, sharedApp);
    final setAccessoryOk = mac.sendBoolInt(
      sharedApp,
      mac.sel('setActivationPolicy:'),
      kNSApplicationActivationPolicyAccessory,
    );
    final policyWhileAccessory = mac.sendInt(
      sharedApp,
      mac.sel('activationPolicy'),
    );
    final setRegularOk = mac.sendBoolInt(
      sharedApp,
      mac.sel('setActivationPolicy:'),
      kNSApplicationActivationPolicyRegular,
    );
    final policyAfterRestore = mac.sendInt(
      sharedApp,
      mac.sel('activationPolicy'),
    );

    mac.sendVoidId(systemBar, mac.sel('removeStatusItem:'), statusItem);
    final activeAfterRemove = _hasActiveStatusBarItem(mac, sharedApp);

    return MacOSActivationPolicyProbeResult(
      detectedStatusBarWindowWhileActive: activeBeforeRemove,
      switchedToAccessoryPolicy:
          setAccessoryOk &&
          policyWhileAccessory == kNSApplicationActivationPolicyAccessory,
      restoredRegularPolicy:
          setRegularOk &&
          policyAfterRestore == kNSApplicationActivationPolicyRegular,
      clearedStatusBarWindowAfterRemove: !activeAfterRemove,
    );
  } finally {
    mac.sendBoolInt(sharedApp, mac.sel('setActivationPolicy:'), previousPolicy);
  }
}

/// Activation call plan for `NSApplication` across macOS 13 Ventura through
/// macOS 27 `Golden Gate`+.
class MacOSActivationPlan {
  /// Creates a [MacOSActivationPlan].
  const MacOSActivationPlan({
    required this.callActivate,
    required this.callActivateIgnoringOtherApps,
  });

  /// Whether `-[NSApplication activate]` (macOS 14+) should be invoked.
  final bool callActivate;

  /// Whether `-[NSApplication activateIgnoringOtherApps:]` should be invoked.
  final bool callActivateIgnoringOtherApps;
}

/// Resolves which `NSApplication` activation selectors to invoke.
///
/// On macOS 14 Sonoma through macOS 27+, `activateIgnoringOtherApps:` still
/// exists in the Objective-C runtime class table (`class_getInstanceMethod` is
/// non-null) even though WindowServer treats it as a deprecated hint;
/// `-[NSApplication activate]` MUST therefore be invoked whenever present
/// instead of returning early after `activateIgnoringOtherApps:`.
MacOSActivationPlan resolveMacOSActivationPlan({
  required bool hasActivateSelector,
  required bool hasActivateIgnoringSelector,
}) {
  return MacOSActivationPlan(
    callActivate: hasActivateSelector,
    callActivateIgnoringOtherApps: hasActivateIgnoringSelector,
  );
}

bool _isCandidateAppWindow(MacOSAppKitBindings mac, ffi.Pointer<ffi.Void> win) {
  if (win == ffi.nullptr) return false;
  if (_isStatusBarWindow(mac, win)) return false;
  final vc = mac.sendId(win, mac.sel('contentViewController'));
  if (vc != ffi.nullptr) return true;
  final mask = mac.sendUInt(win, mac.sel('styleMask'));
  return (mask & kNSWindowStyleMaskTitled) != 0;
}

/// Resolves the current process's primary `NSWindow*` on macOS, falling back to
/// `[[NSApplication sharedApplication] windows]` when hidden to the tray via
/// `orderOut:` or when another application is active.
ffi.Pointer<ffi.Void> resolveMacOSPrimaryWindowHandle() {
  final mac = MacOSAppKitBindings.instance;
  if (mac == null) return ffi.nullptr;
  try {
    final sharedApp = mac.runningNSApp();
    if (sharedApp == ffi.nullptr) return ffi.nullptr;

    final mainWin = mac.sendId(sharedApp, mac.sel('mainWindow'));
    if (_isCandidateAppWindow(mac, mainWin)) return mainWin;

    final keyWin = mac.sendId(sharedApp, mac.sel('keyWindow'));
    if (_isCandidateAppWindow(mac, keyWin)) return keyWin;

    final windows = mac.sendId(sharedApp, mac.sel('windows'));
    if (windows == ffi.nullptr) return ffi.nullptr;
    final count = mac.sendUInt(windows, mac.sel('count'));
    if (count <= 0) return ffi.nullptr;

    final selAt = mac.sel('objectAtIndex:');
    final selVc = mac.sel('contentViewController');
    for (var i = 0; i < count; i++) {
      final candidate = mac.sendIdUInt(windows, selAt, i);
      if (candidate != ffi.nullptr &&
          mac.sendId(candidate, selVc) != ffi.nullptr) {
        return candidate;
      }
    }
    for (var i = 0; i < count; i++) {
      final candidate = mac.sendIdUInt(windows, selAt, i);
      if (_isCandidateAppWindow(mac, candidate)) {
        return candidate;
      }
    }
  } catch (error, stackTrace) {
    NativeCoreDiagnostics.report(
      'resolveMacOSPrimaryWindowHandle',
      error,
      stackTrace,
    );
  }
  return ffi.nullptr;
}

/// AppKit (`NSWindow` / `NSApplication`) implementation of
/// [WindowPlatformAdapter] for macOS 13 Ventura through macOS 27+.
class MacOSWindowAdapter implements WindowPlatformAdapter {
  /// Creates a [MacOSWindowAdapter] wrapping [nativeHandle] (`NSWindow*`).
  MacOSWindowAdapter(this.nativeHandle);

  @override
  final ffi.Pointer<ffi.Void> nativeHandle;

  @override
  bool get isNative => nativeHandle != ffi.nullptr;

  bool _ownsDelegateProperty = false;
  bool _desiredVisible = true;
  bool _switchedToAccessoryOnHide = false;
  TitleBarStyle _titleBarStyle = TitleBarStyle.normal;
  bool _isWindowControlButtonsVisible = true;
  NativeColor _backgroundColor = const NativeColor(0x00000000);
  NativeSize _minimumSize = const NativeSize(500, 300);
  bool _isVisibleInTaskbar = true;
  String _title = '';
  NativeRect _fallbackBounds = const NativeRect(0, 0, 1280, 850);

  @override
  void attach(WindowAdapterEventSink sink) {
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    _ownsDelegateProperty = MacOSWindowDelegateRegistry.instance.attach(
      mac: mac,
      nsWindow: nativeHandle,
      sink: sink,
      onBecameKey: _handleWindowBecameKey,
    );
  }

  void _handleWindowBecameKey() {
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    _desiredVisible = true;
    _restoreRegularActivationPolicyIfNeeded(mac);
  }

  @override
  TitleBarStyle get titleBarStyle => _titleBarStyle;

  @override
  set titleBarStyle(TitleBarStyle style) {
    _titleBarStyle = style;
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      final hidden = style == TitleBarStyle.hidden;
      final currentMask = mac.sendUInt(nativeHandle, mac.sel('styleMask'));
      final targetMask =
          hidden
              ? (currentMask | kNSWindowStyleMaskFullSizeContentView)
              : (currentMask & ~kNSWindowStyleMaskFullSizeContentView);
      if (targetMask != currentMask) {
        mac.sendVoidUInt(nativeHandle, mac.sel('setStyleMask:'), targetMask);
      }
      // NSWindowTitleHidden = 1, NSWindowTitleVisible = 0
      mac.sendVoidInt(
        nativeHandle,
        mac.sel('setTitleVisibility:'),
        hidden ? 1 : 0,
      );
      mac.sendVoidBool(
        nativeHandle,
        mac.sel('setTitlebarAppearsTransparent:'),
        hidden,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.titleBarStyle',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool get isWindowControlButtonsVisible => _isWindowControlButtonsVisible;

  @override
  set isWindowControlButtonsVisible(bool visible) {
    _isWindowControlButtonsVisible = visible;
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      final selStandardButton = mac.sel('standardWindowButton:');
      final selSetHidden = mac.sel('setHidden:');
      // NSWindowCloseButton = 0, NSWindowMiniaturizeButton = 1, NSWindowZoomButton = 2
      for (var kind = 0; kind <= 2; kind++) {
        final btn = mac.sendIdUInt(nativeHandle, selStandardButton, kind);
        if (btn != ffi.nullptr) {
          mac.sendVoidBool(btn, selSetHidden, !visible);
        }
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.isWindowControlButtonsVisible',
        error,
        stackTrace,
      );
    }
  }

  @override
  NativeColor get backgroundColor => _backgroundColor;

  @override
  set backgroundColor(NativeColor color) {
    _backgroundColor = color;
  }

  @override
  bool get isFullScreen {
    if (!isNative) return false;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return false;
    try {
      final mask = mac.sendUInt(nativeHandle, mac.sel('styleMask'));
      return (mask & kNSWindowStyleMaskFullScreen) != 0;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.isFullScreen',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  set isFullScreen(bool value) {
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      if (isFullScreen != value) {
        mac.sendVoidId(nativeHandle, mac.sel('toggleFullScreen:'), ffi.nullptr);
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.setFullScreen',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool get isMaximized => _boolProperty('isZoomed');

  @override
  bool get isMinimized => _boolProperty('isMiniaturized');

  @override
  bool get isVisible => _boolProperty('isVisible');

  @override
  bool get isFocused => _boolProperty('isKeyWindow');

  @override
  NativeSize get minimumSize => _minimumSize;

  @override
  set minimumSize(NativeSize size) {
    _minimumSize = size;
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      mac.sendSetMinSize(
        nativeHandle,
        mac.sel('setMinSize:'),
        size.width,
        size.height,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.minimumSize',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool get isVisibleInTaskbar => _isVisibleInTaskbar;

  @override
  set isVisibleInTaskbar(bool visible) {
    _isVisibleInTaskbar = visible;
    _switchedToAccessoryOnHide = false;
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      final sharedApp = mac.runningNSApp();
      if (sharedApp != ffi.nullptr) {
        mac.sendBoolInt(
          sharedApp,
          mac.sel('setActivationPolicy:'),
          visible
              ? kNSApplicationActivationPolicyRegular
              : kNSApplicationActivationPolicyAccessory,
        );
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.isVisibleInTaskbar',
        error,
        stackTrace,
      );
    }
  }

  @override
  String get title => _title;

  @override
  set title(String value) {
    _title = value;
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      final nsTitle = mac.nsString(value);
      if (nsTitle != ffi.nullptr) {
        mac.sendVoidId(nativeHandle, mac.sel('setTitle:'), nsTitle);
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.title',
        error,
        stackTrace,
      );
    }
  }

  @override
  NativeRect get bounds {
    if (!isNative) return _fallbackBounds;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return _fallbackBounds;
    try {
      final frame = mac.sendRect(nativeHandle, mac.sel('frame'));
      if (frame.size.width > 0 && frame.size.height > 0) {
        final primaryHeight = mac.primaryScreenHeight();
        return _fallbackBounds = NativeRect(
          frame.origin.x,
          primaryHeight - (frame.origin.y + frame.size.height),
          frame.size.width,
          frame.size.height,
        );
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.bounds',
        error,
        stackTrace,
      );
    }
    return _fallbackBounds;
  }

  @override
  set bounds(NativeRect rect) {
    _fallbackBounds = rect;
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      final primaryHeight = mac.primaryScreenHeight();
      final cocoaY = primaryHeight - (rect.top + rect.height);
      mac.sendSetFrame(
        nativeHandle,
        mac.sel('setFrame:display:'),
        rect.left,
        cocoaY,
        rect.width,
        rect.height,
        true,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.setBounds',
        error,
        stackTrace,
      );
    }
  }

  @override
  void setSize(NativeSize size, {required bool animate}) {
    final current = bounds;
    _fallbackBounds = NativeRect(
      current.left,
      current.top,
      size.width,
      size.height,
    );
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      final primaryHeight = mac.primaryScreenHeight();
      final cocoaY = primaryHeight - (current.top + size.height);
      mac.sendSetFrameAnimate(
        nativeHandle,
        mac.sel('setFrame:display:animate:'),
        current.left,
        cocoaY,
        size.width,
        size.height,
        true,
        animate,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.setSize',
        error,
        stackTrace,
      );
    }
  }

  @override
  void maximize() {
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      if (!isMaximized) {
        mac.sendVoidId(nativeHandle, mac.sel('zoom:'), ffi.nullptr);
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.maximize',
        error,
        stackTrace,
      );
    }
  }

  @override
  void unmaximize() {
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      if (isMaximized) {
        mac.sendVoidId(nativeHandle, mac.sel('zoom:'), ffi.nullptr);
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.unmaximize',
        error,
        stackTrace,
      );
    }
  }

  @override
  void minimize() {
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      mac.sendVoidId(nativeHandle, mac.sel('miniaturize:'), ffi.nullptr);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.minimize',
        error,
        stackTrace,
      );
    }
  }

  @override
  void restore() {
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      if (isMinimized) {
        mac.sendVoidId(nativeHandle, mac.sel('deminiaturize:'), ffi.nullptr);
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.restore',
        error,
        stackTrace,
      );
    }
  }

  @override
  void show() {
    _desiredVisible = true;
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      _restoreRegularActivationPolicyIfNeeded(mac);
      if (isMinimized) {
        mac.sendVoidId(nativeHandle, mac.sel('deminiaturize:'), ffi.nullptr);
      }
      mac.sendVoidBool(nativeHandle, mac.sel('setIsVisible:'), true);
      _activateAppAndOrderFront(mac);
      try {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_desiredVisible || !isNative) return;
          if (!isFocused) {
            _restoreRegularActivationPolicyIfNeeded(mac);
            _activateAppAndOrderFront(mac);
          }
        });
        WidgetsBinding.instance.scheduleFrame();
      } catch (error, stackTrace) {
        NativeCoreDiagnostics.report(
          'MacOSWindowAdapter.showPostFrame',
          error,
          stackTrace,
        );
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.show',
        error,
        stackTrace,
      );
    }
  }

  @override
  void hide() {
    _desiredVisible = false;
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      mac.sendVoidBool(nativeHandle, mac.sel('setIsVisible:'), false);
      mac.sendVoidId(nativeHandle, mac.sel('orderOut:'), ffi.nullptr);
      _switchToAccessoryPolicyIfTrayActive(mac);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.hide',
        error,
        stackTrace,
      );
    }
  }

  @override
  void focus() {
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      _restoreRegularActivationPolicyIfNeeded(mac);
      if (isMinimized) {
        mac.sendVoidId(nativeHandle, mac.sel('deminiaturize:'), ffi.nullptr);
      }
      _activateAppAndOrderFront(mac);
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.focus',
        error,
        stackTrace,
      );
    }
  }

  void _switchToAccessoryPolicyIfTrayActive(MacOSAppKitBindings mac) {
    final sharedApp = mac.runningNSApp();
    if (sharedApp == ffi.nullptr) return;
    if (!shouldSwitchMacOSActivationPolicyOnHide(
      hasActiveStatusItem: _hasActiveStatusBarItem(mac, sharedApp),
      hasOtherVisibleAppWindow: _hasOtherVisibleAppWindow(
        mac,
        sharedApp,
        excluding: nativeHandle,
      ),
      isVisibleInTaskbar: _isVisibleInTaskbar,
    )) {
      return;
    }
    _switchedToAccessoryOnHide = true;
    mac.sendBoolInt(
      sharedApp,
      mac.sel('setActivationPolicy:'),
      kNSApplicationActivationPolicyAccessory,
    );
  }

  void _restoreRegularActivationPolicyIfNeeded(MacOSAppKitBindings mac) {
    final sharedApp = mac.runningNSApp();
    if (sharedApp == ffi.nullptr) return;
    final currentPolicy = mac.sendInt(sharedApp, mac.sel('activationPolicy'));
    if (!shouldRestoreMacOSActivationPolicyOnShow(
      switchedToAccessoryOnHide: _switchedToAccessoryOnHide,
      isVisibleInTaskbar: _isVisibleInTaskbar,
      currentActivationPolicy: currentPolicy,
    )) {
      return;
    }
    _switchedToAccessoryOnHide = false;
    mac.sendBoolInt(
      sharedApp,
      mac.sel('setActivationPolicy:'),
      kNSApplicationActivationPolicyRegular,
    );
  }

  @override
  void destroyNativeWindow() {
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      mac.sendVoid(nativeHandle, mac.sel('close'));
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.destroyNativeWindow',
        error,
        stackTrace,
      );
    }
  }

  @override
  void startDragging() {
    if (!isNative) return;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return;
    try {
      final app = mac.runningNSApp();
      if (app == ffi.nullptr) return;
      final currentEvent = mac.sendId(app, mac.sel('currentEvent'));
      if (currentEvent == ffi.nullptr) return;
      final eventType = mac.sendUInt(currentEvent, mac.sel('type'));
      if (eventType == kNSEventTypeLeftMouseDown ||
          eventType == kNSEventTypeLeftMouseDragged) {
        mac.sendVoidId(
          nativeHandle,
          mac.sel('performWindowDragWithEvent:'),
          currentEvent,
        );
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.startDragging',
        error,
        stackTrace,
      );
    }
  }

  @override
  bool showSystemMenu(NativeOffset position) => false;

  void _activateAppAndOrderFront(MacOSAppKitBindings mac) {
    final sharedApp = mac.runningNSApp();
    if (sharedApp != ffi.nullptr) {
      final appCls = mac.objectGetClass(sharedApp);
      if (appCls != ffi.nullptr) {
        final selActivate = mac.sel('activate');
        final selActivateIgnoring = mac.sel('activateIgnoringOtherApps:');
        final plan = resolveMacOSActivationPlan(
          hasActivateSelector:
              mac.classGetInstanceMethod(appCls, selActivate) != ffi.nullptr,
          hasActivateIgnoringSelector:
              mac.classGetInstanceMethod(appCls, selActivateIgnoring) !=
              ffi.nullptr,
        );
        if (plan.callActivate) {
          mac.sendVoid(sharedApp, selActivate);
        }
        if (plan.callActivateIgnoringOtherApps) {
          mac.sendVoidBool(sharedApp, selActivateIgnoring, true);
        }
      }
    }
    mac.sendVoidId(nativeHandle, mac.sel('makeKeyAndOrderFront:'), ffi.nullptr);
    mac.sendVoid(nativeHandle, mac.sel('orderFrontRegardless'));
  }

  bool _boolProperty(String selectorName) {
    if (!isNative) return false;
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return false;
    try {
      return mac.sendBool(nativeHandle, mac.sel(selectorName));
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowAdapter.$selectorName',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  void dispose() {
    if (!isNative) return;
    MacOSWindowDelegateRegistry.instance.detach(
      mac: MacOSAppKitBindings.instance,
      nsWindow: nativeHandle,
      ownsDelegateProperty: _ownsDelegateProperty,
    );
    _ownsDelegateProperty = false;
  }
}
