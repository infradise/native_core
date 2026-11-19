import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_core/native_core.dart';
// ignore: implementation_imports
import 'package:native_core/src/testing/native_core_testing.dart';

void main() {
  group('SingleInstance cross-platform primitives and Unix socket IPC', () {
    test(
      'sanitizeSingleInstanceToken produces safe bounded tokens and distinct hashes for similar appIds',
      () {
        final tokenA = sanitizeSingleInstanceToken('com.example/desktop_app');
        final tokenB = sanitizeSingleInstanceToken('com.example_desktop_app');
        expect(tokenA, isNot(equals(tokenB)));
        expect(tokenA.contains('/'), isFalse);
        expect(tokenA.contains(r'\'), isFalse);

        final veryLong = sanitizeSingleInstanceToken('a' * 300);
        expect(veryLong.length, lessThanOrEqualTo(49));
      },
    );

    test(
      'SecondInstancePayload round-trips multilingual CLI arguments and workingDirectory',
      () {
        const original = SecondInstancePayload(
          arguments: <String>['--new-window', 'C:\\경로\\파일.yaml', '🚀'],
          workingDirectory: r'C:\Users\demo\workspace\desktop-app',
        );
        final encoded = original.encodeJson();
        final decoded = SecondInstancePayload.tryDecodeJson(encoded);
        expect(decoded, isNotNull);
        expect(decoded!.arguments, equals(original.arguments));
        expect(decoded.workingDirectory, equals(original.workingDirectory));
        expect(SecondInstancePayload.tryDecodeJson('not-json'), isNull);
      },
    );

    test(
      'resolveUnixSingleInstanceSocketPath stays strictly under 104-byte sockaddr_un limit and strips trailing slashes',
      () {
        final linuxXdg = resolveUnixSingleInstanceSocketPath(
          'com.example.desktop_app',
          environment: const <String, String>{
            'XDG_RUNTIME_DIR': '/run/user/1000/',
          },
          isLinuxOverride: true,
        );
        expect(linuxXdg, startsWith('/run/user/1000/nc_si_'));
        expect(linuxXdg.contains('//'), isFalse);
        expect(linuxXdg.length, lessThan(100));

        final macTrailingSlash = resolveUnixSingleInstanceSocketPath(
          'com.example.desktop_app',
          environment: const <String, String>{'USER': 'demo'},
          tempDirectoryPath: '/var/tmp/custom/',
          isLinuxOverride: false,
        );
        expect(macTrailingSlash, startsWith('/var/tmp/custom/nc_si_'));
        expect(macTrailingSlash.contains('//'), isFalse);
        expect(macTrailingSlash.length, lessThan(100));

        final longTmpFallback = resolveUnixSingleInstanceSocketPath(
          'com.example.desktop_app',
          environment: const <String, String>{'USER': 'developer'},
          tempDirectoryPath: '/very/deeply/nested/${'dir/' * 25}tmp',
          isLinuxOverride: false,
        );
        expect(longTmpFallback, startsWith('/tmp/nc_si_'));
        expect(longTmpFallback.length, lessThan(100));
      },
    );

    test(
      'Application.instance.ensureSingleInstance bypasses locking when InstanceMode.multiInstance is selected',
      () async {
        final first = await Application.instance.ensureSingleInstance(
          appId: 'com.example.desktop_app.multi_test',
          mode: InstanceMode.multiInstance,
          exitSecondaryProcess: false,
        );
        final second = await Application.instance.ensureSingleInstance(
          appId: 'com.example.desktop_app.multi_test',
          mode: InstanceMode.multiInstance,
          exitSecondaryProcess: false,
        );
        expect(first, isTrue);
        expect(second, isTrue);
      },
    );

    test(
      'UnixSingleInstanceCoordinator enforces primary ownership, forwards Secondary payload, and recovers stale socket',
      () async {
        // Unix domain sockets are supported natively on Linux, macOS, and
        // modern Windows 10/11 builds.
        final tempDir = Directory.systemTemp.createTempSync('nc_si_test_');
        final sockPath = '${tempDir.path}${Platform.pathSeparator}si.sock';
        final primary = UnixSingleInstanceCoordinator(
          socketPathOverride: sockPath,
        );
        final secondary = UnixSingleInstanceCoordinator(
          socketPathOverride: sockPath,
        );

        try {
          var activatedCount = 0;
          SecondInstancePayload? received;

          final acquiredPrimary = await primary.acquireOrForward(
            token: 'unix_test_token',
            payload: const SecondInstancePayload(
              arguments: <String>['--primary'],
              workingDirectory: '/primary',
            ),
            activateExistingWindow: true,
            onActivatePrimaryWindow: () => activatedCount++,
            onSecondInstance: (p) => received = p,
          );
          expect(acquiredPrimary, isTrue);

          final acquiredSecondary = await secondary.acquireOrForward(
            token: 'unix_test_token',
            payload: const SecondInstancePayload(
              arguments: <String>['--new-window', 'cluster.yaml'],
              workingDirectory: '/secondary',
            ),
            activateExistingWindow: true,
            onActivatePrimaryWindow: () {},
            onSecondInstance: null,
          );
          expect(acquiredSecondary, isFalse);
          expect(activatedCount, equals(1));
          expect(received, isNotNull);
          expect(
            received!.arguments,
            equals(const <String>['--new-window', 'cluster.yaml']),
          );
          expect(received!.workingDirectory, equals('/secondary'));

          await primary.release();

          // Simulate a stale socket file left behind after SIGKILL:
          File(sockPath).writeAsStringSync('stale');
          final recovered = UnixSingleInstanceCoordinator(
            socketPathOverride: sockPath,
          );
          try {
            final promoted = await recovered.acquireOrForward(
              token: 'unix_test_token',
              payload: const SecondInstancePayload(
                arguments: <String>[],
                workingDirectory: '',
              ),
              activateExistingWindow: true,
              onActivatePrimaryWindow: () {},
              onSecondInstance: null,
            );
            expect(promoted, isTrue);
          } finally {
            await recovered.release();
          }
        } finally {
          await primary.release();
          await secondary.release();
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      },
    );

    test(
      'WindowsSingleInstanceCoordinator acquires kernel mutex, blocks cross-thread secondary, and delivers WM_COPYDATA payload on Windows',
      () async {
        if (!Platform.isWindows) return;

        final expectedCdsSize =
            debugWin32CopyDataStructSize == 24 ||
            debugWin32CopyDataStructSize == 12;
        expect(expectedCdsSize, isTrue);

        final uniqueToken = sanitizeSingleInstanceToken(
          'com.example.desktop_app.win_si_${DateTime.now().microsecondsSinceEpoch}',
        );
        final primary = WindowsSingleInstanceCoordinator();
        var activateCalls = 0;
        SecondInstancePayload? delivered;

        try {
          final isPrimary = await primary.acquireOrForward(
            token: uniqueToken,
            payload: const SecondInstancePayload(
              arguments: <String>[],
              workingDirectory: '',
            ),
            activateExistingWindow: true,
            onActivatePrimaryWindow: () => activateCalls++,
            onSecondInstance: (p) => delivered = p,
          );
          expect(isPrimary, isTrue);

          // 1. Verify live WM_COPYDATA + AllowSetForegroundWindow IPC delivery
          // to Primary's hidden host HWND:
          final sentOk =
              await WindowsSingleInstanceCoordinator.sendPayloadToWindowsPrimary(
                token: uniqueToken,
                payload: const SecondInstancePayload(
                  arguments: <String>['--open-k8s', '한글경로.yaml'],
                  workingDirectory: r'C:\Work',
                ),
              );
          expect(sentOk, isTrue);
          expect(activateCalls, equals(1));
          expect(delivered, isNotNull);
          expect(
            delivered!.arguments,
            equals(const <String>['--open-k8s', '한글경로.yaml']),
          );
          expect(delivered!.workingDirectory, equals(r'C:\Work'));

          // 2. Verify cross-OS-thread Win32 Named Mutex contention returns
          // `false` (`WAIT_TIMEOUT`) while Primary holds ownership, and `true`
          // immediately after `primary.release()` frees the mutex:
          final canAcquireWhileHeld = await Isolate.run<bool>(
            () => debugCanAcquireWindowsSingleInstanceMutex(uniqueToken),
          );
          expect(canAcquireWhileHeld, isFalse);

          await primary.release();

          final canAcquireAfterRelease = await Isolate.run<bool>(
            () => debugCanAcquireWindowsSingleInstanceMutex(uniqueToken),
          );
          expect(canAcquireAfterRelease, isTrue);
        } finally {
          await primary.release();
        }
      },
    );
  });
}
