import 'dart:async' show Timer;
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../../diagnostics.dart';
import '../../ffi/native_memory.dart';
import '../../models.dart';
import '../window_adapter.dart';
import 'macos_appkit_bindings.dart';

/// Wakes Flutter's macOS `CFRunLoop` / Dart microtask queue immediately after a
/// synchronous `NativeCallable.isolateLocal` AppKit callback cancels a close
/// request and queues async Dart work (such as Close-to-Tray `window.hide()`).
///
/// Without an explicit timer + frame wakeup, returning `NO` from
/// `windowShouldClose:` while the pointer stays over AppKit's red traffic-light
/// close button (`_NSThemeCloseWidget`) leaves microtasks stranded until the
/// cursor exits into `FlutterView`.
void _wakeFlutterRunLoop() {
  Timer.run(() {});
  try {
    WidgetsBinding.instance
      ..ensureVisualUpdate()
      ..scheduleFrame();
  } catch (_) {
    // WidgetsBinding may not be initialized in headless Dart VM tests.
  }
}

/// Verifies on macOS that `libobjc.A.dylib` resolved `class_replaceMethod`
/// (required for Hot Restart-safe delegate trampoline rebinding).
bool debugHasMacOSReplaceMethodSymbol() {
  if (!Platform.isMacOS) return false;
  final mac = MacOSAppKitBindings.instance;
  if (mac == null) return false;
  return mac.getClass('NSObject') != ffi.nullptr;
}

/// Result of [debugRunMacOSWindowShouldCloseProbe].
class MacOSWindowCloseProbeResult {
  /// Creates a [MacOSWindowCloseProbeResult].
  const MacOSWindowCloseProbeResult({
    required this.cancelReturnedFalse,
    required this.allowReturnedTrue,
    required this.becameKeyDispatched,
  });

  /// Whether `windowShouldClose:` returned `NO` when the sink cancelled close.
  final bool cancelReturnedFalse;

  /// Whether `windowShouldClose:` returned `YES` when the sink allowed close.
  final bool allowReturnedTrue;

  /// Whether `onWindowDidBecomeKeyNotification:` invoked `onBecameKey`.
  final bool becameKeyDispatched;
}

class _ProbeEventSink implements WindowAdapterEventSink {
  _ProbeEventSink({required this.allowClose});

  bool allowClose;

  @override
  bool dispatchCloseRequested() => allowClose;

  @override
  void notifyNativeMoved(NativeOffset position) {}
}

/// Live macOS FFI probe exercising Objective-C `objc_msgSend` dispatch through
/// `NativeCoreWindowDelegate` (`windowShouldClose:` cancel/allow and
/// `onWindowDidBecomeKeyNotification:`).
MacOSWindowCloseProbeResult? debugRunMacOSWindowShouldCloseProbe() {
  if (!Platform.isMacOS) return null;
  final mac = MacOSAppKitBindings.instance;
  if (mac == null) return null;

  final nsObjectCls = mac.getClass('NSObject');
  if (nsObjectCls == ffi.nullptr) return null;
  final sentinelWindow = mac.sendId(
    mac.sendId(nsObjectCls, mac.sel('alloc')),
    mac.sel('init'),
  );
  if (sentinelWindow == ffi.nullptr) return null;

  final registry = MacOSWindowDelegateRegistry.instance;
  final sink = _ProbeEventSink(allowClose: false);
  var becameKey = false;
  try {
    final delegate = registry._ensureDelegateInstance(mac);
    if (delegate == ffi.nullptr) return null;
    registry._entries[sentinelWindow.address] = (
      window: sentinelWindow,
      sink: sink,
      onBecameKey: () => becameKey = true,
    );

    final sendBoolId =
        ffi.DynamicLibrary.open('/usr/lib/libobjc.A.dylib')
            .lookup<ffi.NativeFunction<ffi.Void Function()>>('objc_msgSend')
            .cast<
              ffi.NativeFunction<
                ffi.Bool Function(
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                )
              >
            >()
            .asFunction<
              bool Function(
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
              )
            >();

    final cancelRes = sendBoolId(
      delegate,
      mac.sel('windowShouldClose:'),
      sentinelWindow,
    );
    sink.allowClose = true;
    final allowRes = sendBoolId(
      delegate,
      mac.sel('windowShouldClose:'),
      sentinelWindow,
    );

    final nsNotificationCls = mac.getClass('NSNotification');
    if (nsNotificationCls != ffi.nullptr) {
      final name = mac.nsString('NSWindowDidBecomeKeyNotification');
      final sendId2 =
          ffi.DynamicLibrary.open('/usr/lib/libobjc.A.dylib')
              .lookup<ffi.NativeFunction<ffi.Void Function()>>('objc_msgSend')
              .cast<
                ffi.NativeFunction<
                  ffi.Pointer<ffi.Void> Function(
                    ffi.Pointer<ffi.Void>,
                    ffi.Pointer<ffi.Void>,
                    ffi.Pointer<ffi.Void>,
                    ffi.Pointer<ffi.Void>,
                  )
                >
              >()
              .asFunction<
                ffi.Pointer<ffi.Void> Function(
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                )
              >();
      final note = sendId2(
        nsNotificationCls,
        mac.sel('notificationWithName:object:'),
        name,
        sentinelWindow,
      );
      if (note != ffi.nullptr) {
        mac.sendVoidId(
          delegate,
          mac.sel('onWindowDidBecomeKeyNotification:'),
          note,
        );
      }
    }

    return MacOSWindowCloseProbeResult(
      cancelReturnedFalse: !cancelRes,
      allowReturnedTrue: allowRes,
      becameKeyDispatched: becameKey,
    );
  } finally {
    registry._entries.remove(sentinelWindow.address);
    mac.sendVoid(sentinelWindow, mac.sel('release'));
  }
}

/// Result of [debugRunMacOSWindowDetachForAppExitProbe].
class MacOSWindowDetachProbeResult {
  /// Creates a [MacOSWindowDetachProbeResult].
  const MacOSWindowDetachProbeResult({
    required this.receivedNotificationBeforeDetach,
    required this.receivedNotificationAfterDetach,
    required this.windowShouldCloseAfterDetachReturnedTrue,
  });

  /// Whether posting `NSWindowDidBecomeKeyNotification` through
  /// `NSNotificationCenter.defaultCenter` fired `onBecameKey` while attached.
  final bool receivedNotificationBeforeDetach;

  /// Whether posting `NSWindowDidBecomeKeyNotification` fired `onBecameKey`
  /// after [MacOSWindowDelegateRegistry.detach] (must be `false`).
  final bool receivedNotificationAfterDetach;

  /// Whether `windowShouldClose:` returns `YES` after detach (must be `true`).
  final bool windowShouldCloseAfterDetachReturnedTrue;
}

/// Live macOS FFI probe verifying that [MacOSWindowDelegateRegistry.detach]
/// unsubscribes `NativeCoreWindowDelegate` from `NSNotificationCenter` and
/// clears close interception before `-[NSApplication terminate:]` shuts down
/// the Dart isolate.
MacOSWindowDetachProbeResult? debugRunMacOSWindowDetachForAppExitProbe() {
  if (!Platform.isMacOS) return null;
  final mac = MacOSAppKitBindings.instance;
  if (mac == null) return null;

  final nsObjectCls = mac.getClass('NSObject');
  final centerCls = mac.getClass('NSNotificationCenter');
  if (nsObjectCls == ffi.nullptr || centerCls == ffi.nullptr) return null;

  final center = mac.sendId(centerCls, mac.sel('defaultCenter'));
  final noteName = mac.nsString('NSWindowDidBecomeKeyNotification');
  if (center == ffi.nullptr || noteName == ffi.nullptr) return null;

  final sentinelWindow = mac.sendId(
    mac.sendId(nsObjectCls, mac.sel('alloc')),
    mac.sel('init'),
  );
  if (sentinelWindow == ffi.nullptr) return null;

  final registry = MacOSWindowDelegateRegistry.instance;
  final sink = _ProbeEventSink(allowClose: false);
  var becameKeyCount = 0;

  final postNotification =
      ffi.DynamicLibrary.open('/usr/lib/libobjc.A.dylib')
          .lookup<ffi.NativeFunction<ffi.Void Function()>>('objc_msgSend')
          .cast<
            ffi.NativeFunction<
              ffi.Void Function(
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
              )
            >
          >()
          .asFunction<
            void Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>,
            )
          >();

  final sendBoolId =
      ffi.DynamicLibrary.open('/usr/lib/libobjc.A.dylib')
          .lookup<ffi.NativeFunction<ffi.Void Function()>>('objc_msgSend')
          .cast<
            ffi.NativeFunction<
              ffi.Bool Function(
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
              )
            >
          >()
          .asFunction<
            bool Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>,
            )
          >();

  try {
    final delegate = registry._ensureDelegateInstance(mac);
    if (delegate == ffi.nullptr) return null;
    registry._entries[sentinelWindow.address] = (
      window: sentinelWindow,
      sink: sink,
      onBecameKey: () => becameKeyCount++,
    );
    registry._registerBecomeKeyObserver(mac, delegate, sentinelWindow);

    postNotification(
      center,
      mac.sel('postNotificationName:object:'),
      noteName,
      sentinelWindow,
    );
    final beforeDetach = becameKeyCount == 1;

    registry.detach(
      mac: mac,
      nsWindow: sentinelWindow,
      ownsDelegateProperty: false,
    );

    becameKeyCount = 0;
    postNotification(
      center,
      mac.sel('postNotificationName:object:'),
      noteName,
      sentinelWindow,
    );
    final afterDetach = becameKeyCount > 0;
    final allowCloseAfterDetach = sendBoolId(
      delegate,
      mac.sel('windowShouldClose:'),
      sentinelWindow,
    );

    return MacOSWindowDetachProbeResult(
      receivedNotificationBeforeDetach: beforeDetach,
      receivedNotificationAfterDetach: afterDetach,
      windowShouldCloseAfterDetachReturnedTrue: allowCloseAfterDetach,
    );
  } finally {
    registry.detach(
      mac: mac,
      nsWindow: sentinelWindow,
      ownsDelegateProperty: false,
    );
    mac.sendVoid(sentinelWindow, mac.sel('release'));
  }
}

/// Manages the Objective-C `NativeCoreWindowDelegate` class and routes
/// `windowShouldClose:`, `windowDidMove:`, and
/// `NSWindowDidBecomeKeyNotification` callbacks by `NSWindow*` address.
class MacOSWindowDelegateRegistry {
  MacOSWindowDelegateRegistry._();

  /// Process-wide singleton registry.
  static final MacOSWindowDelegateRegistry instance =
      MacOSWindowDelegateRegistry._();

  final Map<
    int,
    ({
      ffi.Pointer<ffi.Void> window,
      WindowAdapterEventSink sink,
      void Function()? onBecameKey,
    })
  >
  _entries =
      <
        int,
        ({
          ffi.Pointer<ffi.Void> window,
          WindowAdapterEventSink sink,
          void Function()? onBecameKey,
        })
      >{};

  ffi.Pointer<ffi.Void>? _delegateInstance;
  ffi.NativeCallable<
    ffi.Bool Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
    )
  >?
  _windowShouldCloseCallable;
  ffi.NativeCallable<
    ffi.Void Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
    )
  >?
  _windowDidMoveCallable;
  ffi.NativeCallable<
    ffi.Void Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
    )
  >?
  _windowDidBecomeKeyCallable;

  /// Attaches `windowShouldClose:`, `windowDidMove:`, and
  /// `NSWindowDidBecomeKeyNotification` interception to [nsWindow] and returns
  /// `true` when [nsWindow]'s `delegate` property was directly assigned to
  /// `NativeCoreWindowDelegate`.
  bool attach({
    required MacOSAppKitBindings mac,
    required ffi.Pointer<ffi.Void> nsWindow,
    required WindowAdapterEventSink sink,
    void Function()? onBecameKey,
  }) {
    if (nsWindow == ffi.nullptr) return false;
    _entries[nsWindow.address] = (
      window: nsWindow,
      sink: sink,
      onBecameKey: onBecameKey,
    );

    try {
      final delegate = _ensureDelegateInstance(mac);
      if (delegate == ffi.nullptr) return false;

      _registerBecomeKeyObserver(mac, delegate, nsWindow);

      final existing = mac.sendId(nsWindow, mac.sel('delegate'));
      if (existing == ffi.nullptr) {
        mac.sendVoidId(nsWindow, mac.sel('setDelegate:'), delegate);
        return true;
      }
      if (existing != delegate) {
        // If the host runner or view controller already assigned an
        // `NSWindowDelegate` that lacks `windowShouldClose:`, dynamically add
        // the close interceptor onto its class so Close-to-Tray still works.
        final existingCls = mac.objectGetClass(existing);
        final selShouldClose = mac.sel('windowShouldClose:');
        if (existingCls != ffi.nullptr &&
            mac.classGetInstanceMethod(existingCls, selShouldClose) ==
                ffi.nullptr &&
            _windowShouldCloseCallable != null) {
          NativeMemory.withUtf8CString('B@:@', (types) {
            mac.addMethod(
              existingCls,
              selShouldClose,
              _windowShouldCloseCallable!.nativeFunction.cast(),
              types,
            );
          });
        }
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowDelegateRegistry.attach',
        error,
        stackTrace,
      );
    }
    return false;
  }

  /// Unregisters [nsWindow], removes its `NSWindowDidBecomeKeyNotification`
  /// observer, and clears its `delegate` property if it still points to
  /// `NativeCoreWindowDelegate`.
  void detach({
    required MacOSAppKitBindings? mac,
    required ffi.Pointer<ffi.Void> nsWindow,
    required bool ownsDelegateProperty,
  }) {
    _entries.remove(nsWindow.address);
    if (mac == null || nsWindow == ffi.nullptr) return;
    final delegate = _delegateInstance;
    if (delegate == null || delegate == ffi.nullptr) return;
    try {
      final centerCls = mac.getClass('NSNotificationCenter');
      if (centerCls != ffi.nullptr) {
        final center = mac.sendId(centerCls, mac.sel('defaultCenter'));
        final noteName = mac.nsString('NSWindowDidBecomeKeyNotification');
        if (center != ffi.nullptr && noteName != ffi.nullptr) {
          mac.sendVoidId3(
            center,
            mac.sel('removeObserver:name:object:'),
            delegate,
            noteName,
            nsWindow,
          );
        }
      }
      if (ownsDelegateProperty) {
        final current = mac.sendId(nsWindow, mac.sel('delegate'));
        if (current == delegate) {
          mac.sendVoidId(nsWindow, mac.sel('setDelegate:'), ffi.nullptr);
        }
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowDelegateRegistry.detach',
        error,
        stackTrace,
      );
    }
  }

  void _registerBecomeKeyObserver(
    MacOSAppKitBindings mac,
    ffi.Pointer<ffi.Void> delegate,
    ffi.Pointer<ffi.Void> nsWindow,
  ) {
    final centerCls = mac.getClass('NSNotificationCenter');
    if (centerCls == ffi.nullptr) return;
    final center = mac.sendId(centerCls, mac.sel('defaultCenter'));
    final noteName = mac.nsString('NSWindowDidBecomeKeyNotification');
    if (center == ffi.nullptr || noteName == ffi.nullptr) return;

    mac.sendVoidId3(
      center,
      mac.sel('removeObserver:name:object:'),
      delegate,
      noteName,
      nsWindow,
    );
    mac.sendVoidId4(
      center,
      mac.sel('addObserver:selector:name:object:'),
      delegate,
      mac.sel('onWindowDidBecomeKeyNotification:'),
      noteName,
      nsWindow,
    );
  }

  ffi.Pointer<ffi.Void> _ensureDelegateInstance(MacOSAppKitBindings mac) {
    final existing = _delegateInstance;
    if (existing != null && existing != ffi.nullptr) return existing;

    _windowShouldCloseCallable ??= ffi.NativeCallable<
      ffi.Bool Function(
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
      )
    >.isolateLocal(_onWindowShouldClose, exceptionalReturn: true);
    _windowDidMoveCallable ??= ffi.NativeCallable<
      ffi.Void Function(
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
      )
    >.isolateLocal(_onWindowDidMove);
    _windowDidBecomeKeyCallable ??= ffi.NativeCallable<
      ffi.Void Function(
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
      )
    >.isolateLocal(_onWindowDidBecomeKeyNotification);

    var cls = mac.getClass('NativeCoreWindowDelegate');
    if (cls == ffi.nullptr) {
      final nsObject = mac.getClass('NSObject');
      cls = NativeMemory.withUtf8CString(
        'NativeCoreWindowDelegate',
        (name) => mac.allocateClassPair(nsObject, name, 0),
      );
      NativeMemory.withUtf8CString('B@:@', (types) {
        mac.addMethod(
          cls,
          mac.sel('windowShouldClose:'),
          _windowShouldCloseCallable!.nativeFunction.cast(),
          types,
        );
      });
      NativeMemory.withUtf8CString('v@:@', (types) {
        mac.addMethod(
          cls,
          mac.sel('windowDidMove:'),
          _windowDidMoveCallable!.nativeFunction.cast(),
          types,
        );
        mac.addMethod(
          cls,
          mac.sel('onWindowDidBecomeKeyNotification:'),
          _windowDidBecomeKeyCallable!.nativeFunction.cast(),
          types,
        );
      });
      mac.registerClassPair(cls);
    } else {
      // Across Flutter Hot Restart, the Objective-C runtime retains the
      // previously registered class whose method IMPs point at the terminated
      // Dart isolate's trampolines. Rebind all selectors to this live isolate.
      NativeMemory.withUtf8CString('B@:@', (types) {
        mac.replaceMethod(
          cls,
          mac.sel('windowShouldClose:'),
          _windowShouldCloseCallable!.nativeFunction.cast(),
          types,
        );
      });
      NativeMemory.withUtf8CString('v@:@', (types) {
        mac.replaceMethod(
          cls,
          mac.sel('windowDidMove:'),
          _windowDidMoveCallable!.nativeFunction.cast(),
          types,
        );
        mac.replaceMethod(
          cls,
          mac.sel('onWindowDidBecomeKeyNotification:'),
          _windowDidBecomeKeyCallable!.nativeFunction.cast(),
          types,
        );
      });
    }

    return _delegateInstance = mac.sendId(
      mac.sendId(cls, mac.sel('alloc')),
      mac.sel('init'),
    );
  }

  static bool _onWindowShouldClose(
    ffi.Pointer<ffi.Void> self,
    ffi.Pointer<ffi.Void> cmd,
    ffi.Pointer<ffi.Void> sender,
  ) {
    final entry = instance._entries[sender.address];
    if (entry == null) return true;
    final allowClose = entry.sink.dispatchCloseRequested();
    if (!allowClose) {
      _wakeFlutterRunLoop();
    }
    return allowClose;
  }

  static void _onWindowDidMove(
    ffi.Pointer<ffi.Void> self,
    ffi.Pointer<ffi.Void> cmd,
    ffi.Pointer<ffi.Void> notification,
  ) {
    final mac = MacOSAppKitBindings.instance;
    if (mac == null || notification == ffi.nullptr) return;
    final sender = mac.sendId(notification, mac.sel('object'));
    if (sender == ffi.nullptr) return;
    final entry = instance._entries[sender.address];
    if (entry == null) return;

    final frame = mac.sendRect(sender, mac.sel('frame'));
    if (frame.size.width <= 0 || frame.size.height <= 0) return;
    final primaryHeight = mac.primaryScreenHeight();
    final top = primaryHeight - (frame.origin.y + frame.size.height);
    entry.sink.notifyNativeMoved(NativeOffset(frame.origin.x, top));
  }

  static void _onWindowDidBecomeKeyNotification(
    ffi.Pointer<ffi.Void> self,
    ffi.Pointer<ffi.Void> cmd,
    ffi.Pointer<ffi.Void> notification,
  ) {
    final mac = MacOSAppKitBindings.instance;
    if (mac == null || notification == ffi.nullptr) return;
    final sender = mac.sendId(notification, mac.sel('object'));
    if (sender == ffi.nullptr) return;
    final entry = instance._entries[sender.address];
    entry?.onBecameKey?.call();
  }
}
