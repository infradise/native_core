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
    required this.sendVoidBool,
    required this.sendVoidInt,
    required this.sendVoidUInt,
    required this.sendBool,
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
}
