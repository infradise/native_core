import 'dart:ffi' as ffi;
import 'dart:io';

import '../../diagnostics.dart';
import '../../ffi/native_memory.dart';
import '../../models.dart';
import '../window_adapter.dart';
import 'macos_appkit_bindings.dart';

/// Verifies on macOS that `libobjc.A.dylib` resolved `class_replaceMethod`
/// (required for Hot Restart-safe delegate trampoline rebinding).
bool debugHasMacOSReplaceMethodSymbol() {
  if (!Platform.isMacOS) return false;
  final mac = MacOSAppKitBindings.instance;
  if (mac == null) return false;
  return mac.getClass('NSObject') != ffi.nullptr;
}

/// Manages the Objective-C `NativeCoreWindowDelegate` class and routes
/// `windowShouldClose:` / `windowDidMove:` notifications by `NSWindow*`
/// address.
class MacOSWindowDelegateRegistry {
  MacOSWindowDelegateRegistry._();

  /// Process-wide singleton registry.
  static final MacOSWindowDelegateRegistry instance =
      MacOSWindowDelegateRegistry._();

  final Map<int, ({ffi.Pointer<ffi.Void> window, WindowAdapterEventSink sink})>
  _entries =
      <int, ({ffi.Pointer<ffi.Void> window, WindowAdapterEventSink sink})>{};

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

  /// Attaches `windowShouldClose:` and `windowDidMove:` interception to
  /// [nsWindow] and returns `true` when [nsWindow]'s `delegate` property was
  /// directly assigned to `NativeCoreWindowDelegate`.
  bool attach({
    required MacOSAppKitBindings mac,
    required ffi.Pointer<ffi.Void> nsWindow,
    required WindowAdapterEventSink sink,
  }) {
    if (nsWindow == ffi.nullptr) return false;
    _entries[nsWindow.address] = (window: nsWindow, sink: sink);

    try {
      final delegate = _ensureDelegateInstance(mac);
      if (delegate == ffi.nullptr) return false;

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

  /// Unregisters [nsWindow] and clears its `delegate` property if it still
  /// points to `NativeCoreWindowDelegate`.
  void detach({
    required MacOSAppKitBindings? mac,
    required ffi.Pointer<ffi.Void> nsWindow,
    required bool ownsDelegateProperty,
  }) {
    _entries.remove(nsWindow.address);
    if (!ownsDelegateProperty || mac == null || nsWindow == ffi.nullptr) return;
    final delegate = _delegateInstance;
    if (delegate == null || delegate == ffi.nullptr) return;
    try {
      final current = mac.sendId(nsWindow, mac.sel('delegate'));
      if (current == delegate) {
        mac.sendVoidId(nsWindow, mac.sel('setDelegate:'), ffi.nullptr);
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSWindowDelegateRegistry.detach',
        error,
        stackTrace,
      );
    }
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
      });
      mac.registerClassPair(cls);
    } else {
      // Across Flutter Hot Restart, the Objective-C runtime retains the
      // previously registered class whose method IMPs point at the terminated
      // Dart isolate's trampolines. Rebind both selectors to this live isolate.
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
    return entry.sink.dispatchCloseRequested();
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
}
