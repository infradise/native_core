import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import '../../diagnostics.dart';
import '../../ffi/native_memory.dart';
import '../../single_instance.dart';
import 'windows_win32_bindings.dart';

/// `WM_COPYDATA` (`0x004A`).
const int kWmCopyData = 0x004A;

/// Magic `COPYDATASTRUCT.dwData` tag identifying `native_core` single-instance
/// JSON payloads (`'NCSI' == 0x4E435349`).
const int kNativeCoreCopyDataMagic = 0x4E435349;

/// `WAIT_OBJECT_0` (`0x00000000`).
const int kWaitObject0 = 0x00000000;

/// `WAIT_ABANDONED` (`0x00000080`).
const int kWaitAbandoned = 0x00000080;

/// `WAIT_TIMEOUT` (`0x00000102`).
const int kWaitTimeout = 0x00000102;

/// `SMTO_ABORTIFHUNG` (`0x0002`).
const int kSmtoAbortIfHung = 0x0002;

/// `MSGFLT_ALLOW` (`1`).
const int kMsgFltAllow = 1;

/// `WS_POPUP` (`0x80000000`).
const int kWsPopup = 0x80000000;

const int _kGwlpWndProc = -4;
const int _maxCopyDataBytes = 65536;
const String _ipcWindowClassName = 'NativeCoreSingleInstanceHost';

/// Native Win32 `WNDCLASSEXW` ABI layout.
final class Win32SingleInstanceWndClassExW extends ffi.Struct {
  /// Struct byte size.
  @ffi.Uint32()
  external int cbSize;

  /// Class style flags.
  @ffi.Uint32()
  external int style;

  /// Window procedure pointer.
  external ffi.Pointer<ffi.Void> lpfnWndProc;

  /// Extra class bytes.
  @ffi.Int32()
  external int cbClsExtra;

  /// Extra window bytes.
  @ffi.Int32()
  external int cbWndExtra;

  /// Module instance handle.
  external ffi.Pointer<ffi.Void> hInstance;

  /// Class icon handle.
  external ffi.Pointer<ffi.Void> hIcon;

  /// Class cursor handle.
  external ffi.Pointer<ffi.Void> hCursor;

  /// Class background brush.
  external ffi.Pointer<ffi.Void> hbrBackground;

  /// Default menu name.
  external ffi.Pointer<ffi.Uint16> lpszMenuName;

  /// Window class name.
  external ffi.Pointer<ffi.Uint16> lpszClassName;

  /// Small icon handle.
  external ffi.Pointer<ffi.Void> hIconSm;
}

/// Native Win32 `COPYDATASTRUCT` ABI layout (`24` bytes on 64-bit, `12` bytes
/// on 32-bit).
final class Win32CopyDataStruct extends ffi.Struct {
  /// Application-defined tag ([kNativeCoreCopyDataMagic]).
  @ffi.UintPtr()
  external int dwData;

  /// Byte length of [lpData].
  @ffi.Uint32()
  external int cbData;

  /// Pointer to payload buffer.
  external ffi.Pointer<ffi.Void> lpData;
}

/// Byte size of [Win32CopyDataStruct] exposed for ABI verification tests.
int get debugWin32CopyDataStructSize => ffi.sizeOf<Win32CopyDataStruct>();

/// Probes from a separate OS thread/isolate whether the Win32 Named Mutex for
/// [token] is currently unowned (`true`) or locked by a primary instance
/// (`false`), without registering a `WNDPROC` `NativeCallable` that would keep
/// a temporary worker isolate alive.
bool debugCanAcquireWindowsSingleInstanceMutex(String token) {
  if (!Platform.isWindows) return true;
  final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
  final createMutexW = kernel32.lookupFunction<
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Int32,
      ffi.Pointer<ffi.Uint16>,
    ),
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.Uint16>,
    )
  >('CreateMutexW');
  final waitForSingleObject = kernel32.lookupFunction<
    ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
    int Function(ffi.Pointer<ffi.Void>, int)
  >('WaitForSingleObject');
  final releaseMutex = kernel32.lookupFunction<
    ffi.Int32 Function(ffi.Pointer<ffi.Void>),
    int Function(ffi.Pointer<ffi.Void>)
  >('ReleaseMutex');
  final closeHandle = kernel32.lookupFunction<
    ffi.Int32 Function(ffi.Pointer<ffi.Void>),
    int Function(ffi.Pointer<ffi.Void>)
  >('CloseHandle');

  final mutexName = WindowsSingleInstanceCoordinator.mutexNameForToken(token);
  final hMutex = NativeMemory.withUtf16WString(
    mutexName,
    (ptr) => createMutexW(ffi.nullptr, 0, ptr),
  );
  if (hMutex == ffi.nullptr) return false;
  try {
    final status = waitForSingleObject(hMutex, 0);
    if (status == kWaitObject0 || status == kWaitAbandoned) {
      releaseMutex(hMutex);
      return true;
    }
    return false;
  } finally {
    closeHandle(hMutex);
  }
}

typedef _Win32WndProcNative =
    ffi.IntPtr Function(
      ffi.Pointer<ffi.Void> hwnd,
      ffi.Uint32 msg,
      ffi.UintPtr wParam,
      ffi.IntPtr lParam,
    );

typedef _IpcCopyDataHandler =
    bool Function(ffi.Pointer<Win32CopyDataStruct> cds);

class _Win32SingleInstanceBindings {
  _Win32SingleInstanceBindings._({
    required this.createMutexW,
    required this.waitForSingleObject,
    required this.releaseMutex,
    required this.closeHandle,
    required this.registerClassExW,
    required this.defWindowProcWPtr,
    required this.defWindowProcW,
    required this.allowSetForegroundWindow,
    required this.sendMessageTimeoutW,
    required this.changeWindowMessageFilterEx,
  });

  static _Win32SingleInstanceBindings? _instance;
  static bool _attempted = false;
  static bool _classRegistered = false;

  static final Map<int, _IpcCopyDataHandler> _handlersByHwnd =
      <int, _IpcCopyDataHandler>{};

  static final ffi.NativeCallable<_Win32WndProcNative> _wndProcCallable =
      ffi.NativeCallable<_Win32WndProcNative>.isolateLocal(
        _dispatchWndProc,
        exceptionalReturn: 0,
      );

  static _Win32SingleInstanceBindings? get instance {
    if (!Platform.isWindows) return null;
    if (_attempted) return _instance;
    _attempted = true;

    try {
      final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      final user32 = ffi.DynamicLibrary.open('user32.dll');

      int Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Void>)?
      filterEx;
      try {
        filterEx = user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.Uint32,
            ffi.Pointer<ffi.Void>,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Void>)
        >('ChangeWindowMessageFilterEx');
      } catch (_) {
        filterEx = null;
      }

      return _instance = _Win32SingleInstanceBindings._(
        createMutexW: kernel32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Int32,
            ffi.Pointer<ffi.Uint16>,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            int,
            ffi.Pointer<ffi.Uint16>,
          )
        >('CreateMutexW'),
        waitForSingleObject: kernel32.lookupFunction<
          ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
          int Function(ffi.Pointer<ffi.Void>, int)
        >('WaitForSingleObject'),
        releaseMutex: kernel32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('ReleaseMutex'),
        closeHandle: kernel32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('CloseHandle'),
        registerClassExW: user32.lookupFunction<
          ffi.Uint16 Function(ffi.Pointer<Win32SingleInstanceWndClassExW>),
          int Function(ffi.Pointer<Win32SingleInstanceWndClassExW>)
        >('RegisterClassExW'),
        defWindowProcWPtr: user32.lookup<ffi.Void>('DefWindowProcW'),
        defWindowProcW: user32.lookupFunction<
          ffi.IntPtr Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.UintPtr,
            ffi.IntPtr,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, int, int)
        >('DefWindowProcW'),
        allowSetForegroundWindow: user32
            .lookupFunction<ffi.Int32 Function(ffi.Uint32), int Function(int)>(
              'AllowSetForegroundWindow',
            ),
        sendMessageTimeoutW: user32.lookupFunction<
          ffi.IntPtr Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.UintPtr,
            ffi.IntPtr,
            ffi.Uint32,
            ffi.Uint32,
            ffi.Pointer<ffi.UintPtr>,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            int,
            int,
            int,
            int,
            int,
            ffi.Pointer<ffi.UintPtr>,
          )
        >('SendMessageTimeoutW'),
        changeWindowMessageFilterEx: filterEx,
      );
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'Win32SingleInstanceBindings.load',
        error,
        stackTrace,
      );
      return null;
    }
  }

  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    int,
    ffi.Pointer<ffi.Uint16>,
  )
  createMutexW;
  final int Function(ffi.Pointer<ffi.Void>, int) waitForSingleObject;
  final int Function(ffi.Pointer<ffi.Void>) releaseMutex;
  final int Function(ffi.Pointer<ffi.Void>) closeHandle;
  final int Function(ffi.Pointer<Win32SingleInstanceWndClassExW>)
  registerClassExW;
  final ffi.Pointer<ffi.Void> defWindowProcWPtr;
  final int Function(ffi.Pointer<ffi.Void>, int, int, int) defWindowProcW;
  final int Function(int) allowSetForegroundWindow;
  final int Function(
    ffi.Pointer<ffi.Void>,
    int,
    int,
    int,
    int,
    int,
    ffi.Pointer<ffi.UintPtr>,
  )
  sendMessageTimeoutW;
  final int Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Void>)?
  changeWindowMessageFilterEx;

  ffi.Pointer<ffi.Void> createIpcHostWindow(
    WindowsWin32Bindings base,
    String windowTitle,
    _IpcCopyDataHandler handler,
  ) {
    final hInstance = base.getModuleHandleW(ffi.nullptr);
    return NativeMemory.withUtf16WString(_ipcWindowClassName, (classPtr) {
      if (!_classRegistered) {
        final wcSize = ffi.sizeOf<Win32SingleInstanceWndClassExW>();
        final wc =
            NativeMemory.malloc(wcSize).cast<Win32SingleInstanceWndClassExW>();
        try {
          NativeMemory.zeroFill(wc.cast(), wcSize);
          // Register the window class with process-lifetime `DefWindowProcW` so
          // Flutter Hot Restart never leaves `WNDCLASSEXW.lpfnWndProc` pointing
          // at a terminated Dart isolate trampoline during `CreateWindowExW`.
          wc.ref
            ..cbSize = wcSize
            ..lpfnWndProc = defWindowProcWPtr
            ..hInstance = hInstance
            ..lpszClassName = classPtr;
          registerClassExW(wc);
          _classRegistered = true;
        } finally {
          NativeMemory.free(wc.cast());
        }
      }

      return NativeMemory.withUtf16WString(windowTitle, (titlePtr) {
        final hwnd = base.createWindowExW(
          kWsExToolWindow,
          classPtr,
          titlePtr,
          kWsPopup,
          0,
          0,
          0,
          0,
          ffi.nullptr,
          ffi.nullptr,
          hInstance,
          ffi.nullptr,
        );
        if (hwnd != ffi.nullptr) {
          _handlersByHwnd[hwnd.address] = handler;
          base.setWindowLongPtrW(
            hwnd,
            _kGwlpWndProc,
            _wndProcCallable.nativeFunction.address,
          );
          changeWindowMessageFilterEx?.call(
            hwnd,
            kWmCopyData,
            kMsgFltAllow,
            ffi.nullptr,
          );
        }
        return hwnd;
      });
    });
  }

  void destroyIpcHostWindow(
    WindowsWin32Bindings base,
    ffi.Pointer<ffi.Void> hwnd,
  ) {
    if (hwnd == ffi.nullptr) return;
    _handlersByHwnd.remove(hwnd.address);
    if (base.isWindow(hwnd) != 0) {
      base.setWindowLongPtrW(hwnd, _kGwlpWndProc, defWindowProcWPtr.address);
      base.destroyWindow(hwnd);
    }
  }

  static int _dispatchWndProc(
    ffi.Pointer<ffi.Void> hwnd,
    int msg,
    int wParam,
    int lParam,
  ) {
    final ext = _instance;
    if (ext == null) return 0;
    if (msg == kWmDestroy) {
      _handlersByHwnd.remove(hwnd.address);
      WindowsWin32Bindings.instance?.setWindowLongPtrW(
        hwnd,
        _kGwlpWndProc,
        ext.defWindowProcWPtr.address,
      );
      return ext.defWindowProcW(hwnd, msg, wParam, lParam);
    }
    if (msg == kWmCopyData && lParam != 0) {
      final handler = _handlersByHwnd[hwnd.address];
      if (handler != null) {
        final cds = ffi.Pointer<Win32CopyDataStruct>.fromAddress(lParam);
        if (handler(cds)) {
          return 1;
        }
      }
    }
    return ext.defWindowProcW(hwnd, msg, wParam, lParam);
  }
}

/// Win32 session-scoped Named Mutex (`Local\NativeCore_SI_<token>`) +
/// `AllowSetForegroundWindow` + `WM_COPYDATA` IPC coordinator for Windows 10
/// and Windows 11.
///
/// Uses `CreateMutexW(bInitialOwner = FALSE)` + `WaitForSingleObject(0)` rather
/// than a separate `GetLastError()` FFI call so Dart VM runtime TLS activity
/// between FFI calls can never clobber error codes, and `WAIT_ABANDONED`
/// automatically recovers if a prior instance terminated abnormally.
class WindowsSingleInstanceCoordinator implements SingleInstanceCoordinator {
  /// Creates a [WindowsSingleInstanceCoordinator].
  WindowsSingleInstanceCoordinator();

  ffi.Pointer<ffi.Void> _mutexHandle = ffi.nullptr;
  ffi.Pointer<ffi.Void> _ipcHwnd = ffi.nullptr;
  bool _activateExistingWindow = true;
  void Function()? _onActivatePrimaryWindow;
  void Function(SecondInstancePayload payload)? _onSecondInstance;

  /// Builds the session-local Win32 mutex name for [token].
  static String mutexNameForToken(String token) =>
      'Local\\NativeCore_SI_$token';

  /// Builds the hidden IPC receiver window title for [token].
  static String ipcWindowTitleForToken(String token) =>
      'NativeCore_SI_IPC_$token';

  @override
  Future<bool> acquireOrForward({
    required String token,
    required SecondInstancePayload payload,
    required bool activateExistingWindow,
    required void Function() onActivatePrimaryWindow,
    required void Function(SecondInstancePayload payload)? onSecondInstance,
  }) async {
    _activateExistingWindow = activateExistingWindow;
    _onActivatePrimaryWindow = onActivatePrimaryWindow;
    _onSecondInstance = onSecondInstance;

    if (_mutexHandle != ffi.nullptr) {
      return true;
    }

    final base = WindowsWin32Bindings.instance;
    final ext = _Win32SingleInstanceBindings.instance;
    if (base == null || ext == null) {
      return true;
    }

    final mutexName = mutexNameForToken(token);
    final ipcTitle = ipcWindowTitleForToken(token);

    final hMutex = NativeMemory.withUtf16WString(
      mutexName,
      (namePtr) => ext.createMutexW(ffi.nullptr, 0, namePtr),
    );
    if (hMutex == ffi.nullptr) {
      return true;
    }

    final waitStatus = ext.waitForSingleObject(hMutex, 0);
    if (waitStatus == kWaitObject0 || waitStatus == kWaitAbandoned) {
      _mutexHandle = hMutex;
      _ipcHwnd = ext.createIpcHostWindow(base, ipcTitle, _handleCopyData);
      return true;
    }

    // Secondary instance: release handle and forward activation + arguments to
    // the running Primary instance.
    ext.closeHandle(hMutex);
    await sendPayloadToWindowsPrimary(token: token, payload: payload);
    return false;
  }

  /// Sends [payload] via `AllowSetForegroundWindow` + `WM_COPYDATA` to the
  /// primary instance owning [token]. Exposed for cross-isolate live Win32
  /// verification in `test/`.
  static Future<bool> sendPayloadToWindowsPrimary({
    required String token,
    required SecondInstancePayload payload,
  }) async {
    final base = WindowsWin32Bindings.instance;
    final ext = _Win32SingleInstanceBindings.instance;
    if (base == null || ext == null) return false;

    final ipcTitle = ipcWindowTitleForToken(token);
    var targetHwnd = ffi.nullptr.cast<ffi.Void>();
    for (var attempt = 0; attempt < 10; attempt++) {
      targetHwnd = NativeMemory.withUtf16WString(_ipcWindowClassName, (clsPtr) {
        return NativeMemory.withUtf16WString(ipcTitle, (titlePtr) {
          return base.findWindowExW(ffi.nullptr, ffi.nullptr, clsPtr, titlePtr);
        });
      });
      if (targetHwnd != ffi.nullptr) break;
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    if (targetHwnd == ffi.nullptr) return false;

    final pidPtr =
        NativeMemory.malloc(ffi.sizeOf<ffi.Uint32>()).cast<ffi.Uint32>();
    try {
      pidPtr.value = 0;
      base.getWindowThreadProcessId(targetHwnd, pidPtr);
      final primaryPid = pidPtr.value;
      if (primaryPid != 0) {
        // Delegate our fresh Explorer launch Foreground Lock directly to the
        // Primary process so its ShowWindow + SetForegroundWindow succeeds even
        // when restored from SW_HIDE (Close-to-Tray).
        ext.allowSetForegroundWindow(primaryPid);
      }
    } finally {
      NativeMemory.free(pidPtr.cast());
    }

    final encodedBytes = utf8.encode(payload.encodeJson());
    final byteCount = encodedBytes.length;
    final dataPtr = NativeMemory.malloc(byteCount == 0 ? 1 : byteCount);
    final cdsPtr =
        NativeMemory.malloc(
          ffi.sizeOf<Win32CopyDataStruct>(),
        ).cast<Win32CopyDataStruct>();
    final resultPtr =
        NativeMemory.malloc(ffi.sizeOf<ffi.UintPtr>()).cast<ffi.UintPtr>();

    try {
      if (byteCount > 0) {
        dataPtr
            .cast<ffi.Uint8>()
            .asTypedList(byteCount)
            .setAll(0, encodedBytes);
      }
      cdsPtr.ref
        ..dwData = kNativeCoreCopyDataMagic
        ..cbData = byteCount
        ..lpData = dataPtr.cast();
      resultPtr.value = 0;

      final sent = ext.sendMessageTimeoutW(
        targetHwnd,
        kWmCopyData,
        0,
        cdsPtr.address,
        kSmtoAbortIfHung,
        1500,
        resultPtr,
      );
      return sent != 0 && resultPtr.value == 1;
    } finally {
      NativeMemory.free(resultPtr.cast());
      NativeMemory.free(cdsPtr.cast());
      NativeMemory.free(dataPtr);
    }
  }

  bool _handleCopyData(ffi.Pointer<Win32CopyDataStruct> cds) {
    try {
      if (cds.ref.dwData != kNativeCoreCopyDataMagic) return false;
      final len = cds.ref.cbData;
      if (len < 0 || len > _maxCopyDataBytes) return false;
      var rawJson = '';
      if (len > 0 && cds.ref.lpData != ffi.nullptr) {
        final bytes = cds.ref.lpData.cast<ffi.Uint8>().asTypedList(len);
        rawJson = utf8.decode(bytes, allowMalformed: true);
      }
      final decoded =
          SecondInstancePayload.tryDecodeJson(rawJson) ??
          const SecondInstancePayload(
            arguments: <String>[],
            workingDirectory: '',
          );
      if (_activateExistingWindow) {
        _onActivatePrimaryWindow?.call();
      }
      _onSecondInstance?.call(decoded);
      return true;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'WindowsSingleInstanceCoordinator.handleCopyData',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> release() async {
    final base = WindowsWin32Bindings.instance;
    final ext = _Win32SingleInstanceBindings.instance;

    final hwnd = _ipcHwnd;
    _ipcHwnd = ffi.nullptr;
    if (base != null && ext != null && hwnd != ffi.nullptr) {
      ext.destroyIpcHostWindow(base, hwnd);
    }

    final hMutex = _mutexHandle;
    _mutexHandle = ffi.nullptr;
    if (ext != null && hMutex != ffi.nullptr) {
      ext.releaseMutex(hMutex);
      ext.closeHandle(hMutex);
    }
  }
}
