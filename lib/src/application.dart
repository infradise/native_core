import 'dart:io';

import 'package:flutter/widgets.dart' show WidgetsBinding;

import 'diagnostics.dart';
import 'main_window.dart';
import 'platform/linux/linux_headerbar_grab.dart';
import 'platform/linux/linux_window_adapter.dart';
import 'platform/macos/macos_appkit_bindings.dart';
import 'platform/unix_single_instance.dart';
import 'platform/windows/windows_single_instance.dart';
import 'platform/windows/windows_win32_bindings.dart';
import 'single_instance.dart';

/// Desktop application lifecycle and single-instance process coordinator.
class Application {
  Application._();

  /// Process-wide singleton [Application].
  static final Application instance = Application._();

  final Map<String, SingleInstanceCoordinator> _coordinatorsByToken =
      <String, SingleInstanceCoordinator>{};

  /// Enforces or bypasses single-instance process coordination according to
  /// [mode] (defaults to [InstanceMode.singleInstance]).
  ///
  /// * When [mode] is [InstanceMode.multiInstance], immediately returns `true`
  ///   without acquiring any OS mutex or socket lock.
  /// * When [mode] is [InstanceMode.singleInstance]:
  ///   - **Windows**: Acquires a session-scoped Win32 Named Mutex
  ///     (`Local\NativeCore_SI_<token>`) and listens for `WM_COPYDATA` payloads
  ///     after `AllowSetForegroundWindow` handoff.
  ///   - **Linux / macOS**: Binds a user-scoped Unix Domain Socket with
  ///     automatic `SIGKILL` stale-socket recovery.
  /// * Returns `true` if this process is the primary instance (or on
  ///   non-desktop platforms), or `false` if an existing primary instance was
  ///   activated (automatically calling [quit] when [exitSecondaryProcess] is
  ///   `true`).
  Future<bool> ensureSingleInstance({
    required String appId,
    InstanceMode mode = InstanceMode.singleInstance,
    List<String> arguments = const <String>[],
    bool activateExistingWindow = true,
    bool exitSecondaryProcess = true,
    void Function(SecondInstancePayload payload)? onSecondInstance,
  }) async {
    if (mode == InstanceMode.multiInstance) {
      return true;
    }
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return true;
    }

    final token = sanitizeSingleInstanceToken(appId);
    final existing = _coordinatorsByToken[token];
    if (existing != null) {
      return true;
    }

    final coordinator =
        Platform.isWindows
            ? WindowsSingleInstanceCoordinator()
            : UnixSingleInstanceCoordinator();

    var safeCwd = '';
    try {
      safeCwd = Directory.current.path;
    } catch (_) {
      // Current directory may be unavailable in restricted sandboxes.
    }

    final payload = SecondInstancePayload(
      arguments: List<String>.unmodifiable(arguments),
      workingDirectory: safeCwd,
    );

    final isPrimary = await coordinator.acquireOrForward(
      token: token,
      payload: payload,
      activateExistingWindow: activateExistingWindow,
      onActivatePrimaryWindow: _activatePrimaryMainWindow,
      onSecondInstance: onSecondInstance,
    );

    if (isPrimary) {
      _coordinatorsByToken[token] = coordinator;
      if (Platform.isMacOS) {
        MacOSAppLifecycleObserver.instance.registerWillTerminate(
          releaseSingleInstanceSync,
        );
      }
      return true;
    }

    if (exitSecondaryProcess) {
      quit(0);
    }
    return false;
  }

  /// Releases the single-instance lock held for [appId] (or all held locks when
  /// [appId] is `null`).
  Future<void> releaseSingleInstance([String? appId]) async {
    if (appId != null) {
      final token = sanitizeSingleInstanceToken(appId);
      final coordinator = _coordinatorsByToken.remove(token);
      if (coordinator != null) {
        await coordinator.release();
      }
      if (_coordinatorsByToken.isEmpty && Platform.isMacOS) {
        MacOSAppLifecycleObserver.instance.unregisterWillTerminate(
          releaseSingleInstanceSync,
        );
      }
      return;
    }

    final active = List<SingleInstanceCoordinator>.of(
      _coordinatorsByToken.values,
    );
    _coordinatorsByToken.clear();
    if (Platform.isMacOS) {
      MacOSAppLifecycleObserver.instance.unregisterWillTerminate(
        releaseSingleInstanceSync,
      );
    }
    for (final coordinator in active) {
      await coordinator.release();
    }
  }

  /// Best-effort synchronous release of all held Unix single-instance sockets
  /// during OS termination (`NSApplicationWillTerminateNotification` or
  /// [quit]).
  void releaseSingleInstanceSync() {
    final active = List<SingleInstanceCoordinator>.of(
      _coordinatorsByToken.values,
    );
    _coordinatorsByToken.clear();
    for (final coordinator in active) {
      if (coordinator is UnixSingleInstanceCoordinator) {
        coordinator.releaseSync();
      }
    }
  }

  static void _activatePrimaryMainWindow() {
    try {
      final window = mainWindow;
      if (window == null) return;
      if (window.isMinimized) {
        window.restore();
      }
      window
        ..show()
        ..focus();
      if (Platform.isLinux) {
        hideLinuxNativeTitleBar(window);
      }
      try {
        WidgetsBinding.instance
          ..ensureVisualUpdate()
          ..scheduleFrame();
      } catch (_) {
        // WidgetsBinding may not be initialized in headless Dart VM runs.
      }
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'Application.activatePrimaryMainWindow',
        error,
        stackTrace,
      );
    }
  }

  /// Terminates the native desktop application event loop and exits the process
  /// with [exitCode].
  void quit([int exitCode = 0]) {
    releaseSingleInstanceSync();
    if (Platform.isLinux) {
      quitLinuxApplication();
    } else if (Platform.isWindows) {
      postWindowsQuitMessage(exitCode);
    }
    exit(exitCode);
  }
}
