import 'dart:ffi' as ffi;
import 'dart:io';

import '../../diagnostics.dart';
import '../../display_manager.dart';
import '../../ffi/native_memory.dart';

/// `NSWindowStyleMaskTitled` (`1 << 0`).
const int kNSWindowStyleMaskTitled = 1 << 0;

/// `NSWindowStyleMaskFullScreen` (`1 << 14`).
const int kNSWindowStyleMaskFullScreen = 1 << 14;

/// `NSWindowStyleMaskFullSizeContentView` (`1 << 15`).
const int kNSWindowStyleMaskFullSizeContentView = 1 << 15;

/// `NSEventTypeLeftMouseDown` (`1`).
const int kNSEventTypeLeftMouseDown = 1;

/// `NSEventTypeLeftMouseDragged` (`6`).
const int kNSEventTypeLeftMouseDragged = 6;

/// `NSApplicationActivationPolicyRegular` (`0`) — appears in Dock and owns a
/// menu bar.
const int kNSApplicationActivationPolicyRegular = 0;

/// `NSApplicationActivationPolicyAccessory` (`1`) — hidden from the Dock and
/// application switcher while keeping `NSStatusItem` menu bar icons alive.
const int kNSApplicationActivationPolicyAccessory = 1;

/// `NSApplicationActivationPolicyProhibited` (`2`).
const int kNSApplicationActivationPolicyProhibited = 2;

/// Native `NSPoint` / `CGPoint` ABI layout (`double x, double y`).
final class MacPoint extends ffi.Struct {
  /// Horizontal coordinate in points.
  @ffi.Double()
  external double x;

  /// Vertical coordinate in points (Cocoa bottom-left origin).
  @ffi.Double()
  external double y;
}

/// Native `NSSize` / `CGSize` ABI layout (`double width, double height`).
final class MacSize extends ffi.Struct {
  /// Width in points.
  @ffi.Double()
  external double width;

  /// Height in points.
  @ffi.Double()
  external double height;
}

/// Native `NSRect` / `CGRect` ABI layout (`32` bytes).
final class MacRect extends ffi.Struct {
  /// Origin point of the rectangle.
  external MacPoint origin;

  /// Dimensions of the rectangle.
  external MacSize size;
}

/// One-time cached Objective-C runtime and AppKit symbol + selector table on
/// macOS (`arm64` and `x86_64` Universal Binary ABI-safe).
class MacOSAppKitBindings {
  MacOSAppKitBindings._({
    required this.getClassPtr,
    required this.registerNamePtr,
    required this.objectGetClass,
    required this.classGetName,
    required this.classGetInstanceMethod,
    required this.allocateClassPair,
    required this.registerClassPair,
    required this.addMethod,
    required this.replaceMethod,
    required this.sendId,
    required this.sendId1,
    required this.sendIdUInt,
    required this.sendVoid,
    required this.sendVoidId,
    required this.sendVoidId3,
    required this.sendVoidId4,
    required this.sendVoidBool,
    required this.sendVoidInt,
    required this.sendVoidUInt,
    required this.sendBool,
    required this.sendBoolInt,
    required this.sendInt,
    required this.sendUInt,
    required this.sendDouble,
    required this.sendRect,
    required this.sendSetMinSize,
    required this.sendSetFrame,
    required this.sendSetFrameAnimate,
    required this.scratchSize,
    required this.scratchRect,
  });

  static MacOSAppKitBindings? _instance;
  static bool _attempted = false;

  /// Returns the cached [MacOSAppKitBindings] singleton on macOS, or `null` on
  /// other OSes.
  static MacOSAppKitBindings? get instance {
    if (!Platform.isMacOS) return null;
    if (_attempted) return _instance;
    _attempted = true;

    try {
      try {
        ffi.DynamicLibrary.open(
          '/System/Library/Frameworks/AppKit.framework/AppKit',
        );
      } catch (_) {
        // AppKit may already be linked into the host Flutter runner.
      }
      final objc = ffi.DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
      final msgSend = objc.lookup<ffi.NativeFunction<ffi.Void Function()>>(
        'objc_msgSend',
      );
      // 32-byte `NSRect` return uses `objc_msgSend_stret` on Intel x86_64 and
      // register return `objc_msgSend` on Apple Silicon arm64.
      final msgSendRect =
          ffi.Abi.current() == ffi.Abi.macosX64
              ? objc.lookup<ffi.NativeFunction<ffi.Void Function()>>(
                'objc_msgSend_stret',
              )
              : msgSend;

      final setMinSizeFn =
          msgSend
              .cast<
                ffi.NativeFunction<
                  ffi.Void Function(
                    ffi.Pointer<ffi.Void>,
                    ffi.Pointer<ffi.Void>,
                    MacSize,
                  )
                >
              >()
              .asFunction<
                void Function(
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                  MacSize,
                )
              >();
      final setFrameFn =
          msgSend
              .cast<
                ffi.NativeFunction<
                  ffi.Void Function(
                    ffi.Pointer<ffi.Void>,
                    ffi.Pointer<ffi.Void>,
                    MacRect,
                    ffi.Bool,
                  )
                >
              >()
              .asFunction<
                void Function(
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                  MacRect,
                  bool,
                )
              >();
      final setFrameAnimateFn =
          msgSend
              .cast<
                ffi.NativeFunction<
                  ffi.Void Function(
                    ffi.Pointer<ffi.Void>,
                    ffi.Pointer<ffi.Void>,
                    MacRect,
                    ffi.Bool,
                    ffi.Bool,
                  )
                >
              >()
              .asFunction<
                void Function(
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                  MacRect,
                  bool,
                  bool,
                )
              >();

      final scratchSize =
          NativeMemory.malloc(ffi.sizeOf<MacSize>()).cast<MacSize>();
      final scratchRect =
          NativeMemory.malloc(ffi.sizeOf<MacRect>()).cast<MacRect>();
      if (scratchSize == ffi.nullptr || scratchRect == ffi.nullptr) {
        if (scratchSize != ffi.nullptr) NativeMemory.free(scratchSize.cast());
        if (scratchRect != ffi.nullptr) NativeMemory.free(scratchRect.cast());
        return null;
      }

      return _instance = MacOSAppKitBindings._(
        getClassPtr: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>)
        >('objc_getClass'),
        registerNamePtr: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>)
        >('sel_registerName'),
        objectGetClass: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
        >('object_getClass'),
        classGetName: objc.lookupFunction<
          ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Void>)
        >('class_getName'),
        classGetInstanceMethod: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          )
        >('class_getInstanceMethod'),
        allocateClassPair: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
            ffi.Size,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
            int,
          )
        >('objc_allocateClassPair'),
        registerClassPair: objc.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('objc_registerClassPair'),
        addMethod: objc.lookupFunction<
          ffi.Bool Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
          ),
          bool Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
          )
        >('class_addMethod'),
        replaceMethod: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
          )
        >('class_replaceMethod'),
        sendId:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Pointer<ffi.Void> Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendId1:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Pointer<ffi.Void> Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendIdUInt:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Pointer<ffi.Void> Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.UintPtr,
                    )
                  >
                >()
                .asFunction(),
        sendVoid:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendVoidId:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendVoidId3:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendVoidId4:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendVoidBool:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Bool,
                    )
                  >
                >()
                .asFunction(),
        sendVoidInt:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.IntPtr,
                    )
                  >
                >()
                .asFunction(),
        sendVoidUInt:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.UintPtr,
                    )
                  >
                >()
                .asFunction(),
        sendBool:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Bool Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendBoolInt:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Bool Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.IntPtr,
                    )
                  >
                >()
                .asFunction(),
        sendInt:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.IntPtr Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendUInt:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.UintPtr Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendDouble:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Double Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendRect:
            msgSendRect
                .cast<
                  ffi.NativeFunction<
                    MacRect Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendSetMinSize: (target, selector, w, h) {
          scratchSize.ref
            ..width = w
            ..height = h;
          setMinSizeFn(target, selector, scratchSize.ref);
        },
        sendSetFrame: (target, selector, x, y, w, h, display) {
          scratchRect.ref.origin
            ..x = x
            ..y = y;
          scratchRect.ref.size
            ..width = w
            ..height = h;
          setFrameFn(target, selector, scratchRect.ref, display);
        },
        sendSetFrameAnimate: (target, selector, x, y, w, h, display, animate) {
          scratchRect.ref.origin
            ..x = x
            ..y = y;
          scratchRect.ref.size
            ..width = w
            ..height = h;
          setFrameAnimateFn(
            target,
            selector,
            scratchRect.ref,
            display,
            animate,
          );
        },
        scratchSize: scratchSize,
        scratchRect: scratchRect,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSAppKitBindings.load',
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// `objc_getClass`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>) getClassPtr;

  /// `sel_registerName`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>) registerNamePtr;

  /// `object_getClass`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>) objectGetClass;

  /// `class_getName`.
  final ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Void>) classGetName;

  /// `class_getInstanceMethod`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  classGetInstanceMethod;

  /// `objc_allocateClassPair`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Char>,
    int,
  )
  allocateClassPair;

  /// `objc_registerClassPair`.
  final void Function(ffi.Pointer<ffi.Void>) registerClassPair;

  /// `class_addMethod`.
  final bool Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Char>,
  )
  addMethod;

  /// `class_replaceMethod`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Char>,
  )
  replaceMethod;

  /// `id (*objc_msgSend)(id, SEL)`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  sendId;

  /// `id (*objc_msgSend)(id, SEL, id)`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  sendId1;

  /// `id (*objc_msgSend)(id, SEL, NSUInteger)`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    int,
  )
  sendIdUInt;

  /// `void (*objc_msgSend)(id, SEL)`.
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) sendVoid;

  /// `void (*objc_msgSend)(id, SEL, id)`.
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  sendVoidId;

  /// `void (*objc_msgSend)(id, SEL, id, id, id)` (e.g.
  /// `-[NSNotificationCenter removeObserver:name:object:]`).
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  sendVoidId3;

  /// `void (*objc_msgSend)(id, SEL, id, SEL, id, id)` (e.g.
  /// `-[NSNotificationCenter addObserver:selector:name:object:]`).
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  sendVoidId4;

  /// `void (*objc_msgSend)(id, SEL, BOOL)`.
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, bool)
  sendVoidBool;

  /// `void (*objc_msgSend)(id, SEL, NSInteger)`.
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int)
  sendVoidInt;

  /// `void (*objc_msgSend)(id, SEL, NSUInteger)`.
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int)
  sendVoidUInt;

  /// `BOOL (*objc_msgSend)(id, SEL)`.
  final bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) sendBool;

  /// `BOOL (*objc_msgSend)(id, SEL, NSInteger)`.
  final bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int)
  sendBoolInt;

  /// `NSInteger (*objc_msgSend)(id, SEL)`.
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) sendInt;

  /// `NSUInteger (*objc_msgSend)(id, SEL)`.
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) sendUInt;

  /// `CGFloat (*objc_msgSend)(id, SEL)`.
  final double Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)
  sendDouble;

  /// `NSRect (*objc_msgSend[_stret])(id, SEL)`.
  final MacRect Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) sendRect;

  /// `-[NSWindow setMinSize:]` wrapper.
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    double,
    double,
  )
  sendSetMinSize;

  /// `-[NSWindow setFrame:display:]` wrapper.
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    double,
    double,
    double,
    double,
    bool,
  )
  sendSetFrame;

  /// `-[NSWindow setFrame:display:animate:]` wrapper.
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    double,
    double,
    double,
    double,
    bool,
    bool,
  )
  sendSetFrameAnimate;

  /// Reusable `MacSize` scratch buffer on the main UI thread.
  final ffi.Pointer<MacSize> scratchSize;

  /// Reusable `MacRect` scratch buffer on the main UI thread.
  final ffi.Pointer<MacRect> scratchRect;

  final Map<String, ffi.Pointer<ffi.Void>> _classes =
      <String, ffi.Pointer<ffi.Void>>{};
  final Map<String, ffi.Pointer<ffi.Void>> _selectors =
      <String, ffi.Pointer<ffi.Void>>{};
  ffi.Pointer<ffi.Pointer<ffi.Void>>? _nsAppSymbol;
  bool _nsAppSymbolResolved = false;

  /// Looks up and caches an Objective-C class pointer (`Class`) by [name].
  ///
  /// Only non-null pointers are cached so dynamically registered classes (such
  /// as `NativeCoreWindowDelegate`) can be resolved after registration.
  ffi.Pointer<ffi.Void> getClass(String name) {
    final cached = _classes[name];
    if (cached != null) return cached;
    final resolved = NativeMemory.withUtf8CString(name, getClassPtr);
    if (resolved != ffi.nullptr) {
      _classes[name] = resolved;
    }
    return resolved;
  }

  /// Registers and permanently caches an Objective-C selector (`SEL`) by
  /// [name], eliminating per-frame `malloc` + `sel_registerName` overhead.
  ffi.Pointer<ffi.Void> sel(String name) {
    return _selectors.putIfAbsent(
      name,
      () => NativeMemory.withUtf8CString(name, registerNamePtr),
    );
  }

  /// Converts [value] into a non-null `NSString*`, falling back to `@""` if
  /// `stringWithUTF8String:` returns `nil`.
  ffi.Pointer<ffi.Void> nsString(String value) {
    final cls = getClass('NSString');
    if (cls == ffi.nullptr) return ffi.nullptr;
    final created = NativeMemory.withUtf8CString(
      value,
      (cstr) => sendId1(cls, sel('stringWithUTF8String:'), cstr.cast()),
    );
    if (created != ffi.nullptr) return created;
    return sendId(cls, sel('string'));
  }

  /// Returns `NSApp` only when a GUI `NSApplication` has already been launched
  /// (returning `nullptr` inside headless `flutter_tester` runs).
  ffi.Pointer<ffi.Void> runningNSApp() {
    if (!_nsAppSymbolResolved) {
      _nsAppSymbolResolved = true;
      try {
        _nsAppSymbol = ffi.DynamicLibrary.process()
            .lookup<ffi.Pointer<ffi.Void>>('NSApp');
      } catch (_) {
        _nsAppSymbol = null;
      }
    }
    final sym = _nsAppSymbol;
    if (sym == null || sym == ffi.nullptr) return ffi.nullptr;
    return sym.value;
  }

  /// Queries the primary `NSScreen` height in points for converting between
  /// Cocoa bottom-left coordinates and desktop top-left coordinates.
  double primaryScreenHeight() {
    final nsScreenCls = getClass('NSScreen');
    if (nsScreenCls != ffi.nullptr) {
      final screens = sendId(nsScreenCls, sel('screens'));
      if (screens != ffi.nullptr && sendUInt(screens, sel('count')) > 0) {
        final primary = sendIdUInt(screens, sel('objectAtIndex:'), 0);
        if (primary != ffi.nullptr) {
          final h = sendRect(primary, sel('frame')).size.height;
          if (h > 0) return h;
        }
      }
    }
    final displays = DisplayManager.instance.getAll();
    if (displays.isNotEmpty && displays.first.bounds.height > 0) {
      return displays.first.bounds.height;
    }
    return 1080.0;
  }

  /// Returns the Objective-C runtime class name for [obj], or `null` when
  /// [obj] is `nullptr`.
  String? dartClassName(ffi.Pointer<ffi.Void> obj) {
    if (obj == ffi.nullptr) return null;
    final cls = objectGetClass(obj);
    if (cls == ffi.nullptr) return null;
    final raw = classGetName(cls).cast<ffi.Uint8>();
    if (raw == ffi.nullptr) return null;
    final bytes = <int>[];
    var i = 0;
    while (raw[i] != 0) {
      bytes.add(raw[i]);
      i++;
    }
    return String.fromCharCodes(bytes);
  }
}

/// Observes `NSApplicationWillTerminateNotification` on macOS using a
/// Hot-Restart-safe Objective-C observer class (`NativeCoreAppLifecycleObserver`)
/// so `native_core` automatically releases single-instance Unix sockets when
/// terminated via Dock Quit or `Cmd+Q`.
class MacOSAppLifecycleObserver {
  MacOSAppLifecycleObserver._();

  /// Process-wide singleton observer.
  static final MacOSAppLifecycleObserver instance =
      MacOSAppLifecycleObserver._();

  final Set<void Function()> _willTerminateCallbacks = <void Function()>{};

  ffi.Pointer<ffi.Void>? _observerInstance;
  bool _registeredWithCenter = false;
  ffi.NativeCallable<
    ffi.Void Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
    )
  >?
  _willTerminateCallable;

  /// Registers [callback] to run synchronously when macOS posts
  /// `NSApplicationWillTerminateNotification`.
  bool registerWillTerminate(void Function() callback) {
    if (!Platform.isMacOS) return false;
    _willTerminateCallbacks.add(callback);
    return _ensureRegistered();
  }

  /// Removes a previously registered [callback].
  void unregisterWillTerminate(void Function() callback) {
    _willTerminateCallbacks.remove(callback);
  }

  bool _ensureRegistered() {
    final mac = MacOSAppKitBindings.instance;
    if (mac == null) return false;
    try {
      final observer = _ensureObserverInstance(mac);
      if (observer == ffi.nullptr) return false;
      if (_registeredWithCenter) return true;

      final centerCls = mac.getClass('NSNotificationCenter');
      if (centerCls == ffi.nullptr) return false;
      final defaultCenter = mac.sendId(centerCls, mac.sel('defaultCenter'));
      if (defaultCenter == ffi.nullptr) return false;
      final noteName = mac.nsString('NSApplicationWillTerminateNotification');
      if (noteName == ffi.nullptr) return false;

      mac.sendVoidId4(
        defaultCenter,
        mac.sel('addObserver:selector:name:object:'),
        observer,
        mac.sel('onApplicationWillTerminate:'),
        noteName,
        ffi.nullptr,
      );
      _registeredWithCenter = true;
      return true;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'MacOSAppLifecycleObserver.register',
        error,
        stackTrace,
      );
      return false;
    }
  }

  ffi.Pointer<ffi.Void> _ensureObserverInstance(MacOSAppKitBindings mac) {
    final existing = _observerInstance;
    if (existing != null && existing != ffi.nullptr) return existing;

    _willTerminateCallable ??= ffi.NativeCallable<
      ffi.Void Function(
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
      )
    >.isolateLocal(_onWillTerminate);

    final actionSel = mac.sel('onApplicationWillTerminate:');
    var cls = mac.getClass('NativeCoreAppLifecycleObserver');
    if (cls == ffi.nullptr) {
      final nsObject = mac.getClass('NSObject');
      cls = NativeMemory.withUtf8CString(
        'NativeCoreAppLifecycleObserver',
        (name) => mac.allocateClassPair(nsObject, name, 0),
      );
      NativeMemory.withUtf8CString('v@:@', (types) {
        mac.addMethod(
          cls,
          actionSel,
          _willTerminateCallable!.nativeFunction.cast(),
          types,
        );
      });
      mac.registerClassPair(cls);
    } else {
      NativeMemory.withUtf8CString('v@:@', (types) {
        mac.replaceMethod(
          cls,
          actionSel,
          _willTerminateCallable!.nativeFunction.cast(),
          types,
        );
      });
    }

    return _observerInstance = mac.sendId(
      mac.sendId(cls, mac.sel('alloc')),
      mac.sel('init'),
    );
  }

  static void _onWillTerminate(
    ffi.Pointer<ffi.Void> self,
    ffi.Pointer<ffi.Void> cmd,
    ffi.Pointer<ffi.Void> notification,
  ) {
    final snapshot = List<void Function()>.of(instance._willTerminateCallbacks);
    for (final callback in snapshot) {
      try {
        callback();
      } catch (error, stackTrace) {
        NativeCoreDiagnostics.report(
          'MacOSAppLifecycleObserver.willTerminate',
          error,
          stackTrace,
        );
      }
    }
  }
}

/// Live macOS FFI probe verifying that `NativeCoreAppLifecycleObserver`
/// registers on `NSNotificationCenter.defaultCenter` and dispatches registered
/// termination callbacks through Objective-C `objc_msgSend`.
bool debugRunMacOSWillTerminateObserverProbe() {
  if (!Platform.isMacOS) return false;
  final mac = MacOSAppKitBindings.instance;
  if (mac == null) return false;

  var invoked = false;
  void onTerminate() {
    invoked = true;
  }

  final observer = MacOSAppLifecycleObserver.instance;
  final registered = observer.registerWillTerminate(onTerminate);
  try {
    final target = observer._observerInstance;
    if (!registered || target == null || target == ffi.nullptr) {
      return false;
    }
    mac.sendVoidId(target, mac.sel('onApplicationWillTerminate:'), ffi.nullptr);
    return invoked;
  } finally {
    observer.unregisterWillTerminate(onTerminate);
  }
}
