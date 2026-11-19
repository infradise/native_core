import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:ui' show AppExitResponse, Color, Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:native_core/native_core.dart';
// ignore: implementation_imports
import 'package:native_core/src/ffi/native_memory.dart';
// ignore: implementation_imports
import 'package:native_core/src/testing/native_core_testing.dart';

void main() {
  group('Window facade, models, diagnostics, and NativeMemory', () {
    test('mainWindow safely returns null in headless Dart VM test runner', () {
      expect(() => mainWindow, returnsNormally);
      expect(mainWindow, isNull);
    });

    test(
      'Window.fakeForTesting dispatches lifecycle events and supports EventRequest.cancel()',
      () {
        final window = Window.fakeForTesting();
        final events = <WindowEvent>[];
        final listenerId = window.addListener((event) {
          events.add(event);
          if (event is WindowCloseRequestedEvent) {
            event.request.cancel();
          }
        });

        expect(window.isMaximized, isFalse);
        window.maximize();
        expect(window.isMaximized, isTrue);
        expect(events.last, isA<WindowMaximizedEvent>());

        window.performTitleBarDoubleClick();
        expect(window.isMaximized, isFalse);
        expect(events.last, isA<WindowRestoredEvent>());

        window.setSize(const NativeSize(1024, 768));
        expect(window.bounds.width, 1024);
        expect(window.bounds.height, 768);
        expect(events.last, isA<WindowResizedEvent>());

        window
          ..title = 'Desktop App - Workspace'
          ..minimumSize = const NativeSize(600, 400)
          ..backgroundColor = const NativeColor(0xFF111618)
          ..titleBarStyle = TitleBarStyle.hidden
          ..isWindowControlButtonsVisible = false
          ..isVisibleInTaskbar = false;
        expect(window.title, 'Desktop App - Workspace');
        expect(window.minimumSize, const NativeSize(600, 400));
        expect(window.backgroundColor, const NativeColor(0xFF111618));
        expect(window.titleBarStyle, TitleBarStyle.hidden);
        expect(window.isWindowControlButtonsVisible, isFalse);
        expect(window.isVisibleInTaskbar, isFalse);

        window.close();
        final closeEvent = events.last as WindowCloseRequestedEvent;
        expect(closeEvent.request.isCancelled, isTrue);
        expect(window.isVisible, isTrue);

        window.removeListener(listenerId);
        final countBefore = events.length;
        window.minimize();
        expect(events.length, countBefore);
        window.close();
        expect(window.isVisible, isFalse);
        window.dispose();
      },
    );

    test(
      'NativeSize, NativeOffset, NativeRect, and NativeColor round-trip cleanly',
      () {
        const size = Size(1280, 850);
        expect(size.toNative().toSize(), size);

        const offset = Offset(120, 64);
        expect(offset.toNative().toOffset(), offset);

        const rect = Rect.fromLTWH(10, 20, 800, 600);
        expect(rect.toNative().toRect(), rect);

        const color = Color(0xFF0F172A);
        expect(color.toNative().toColor(), color);
      },
    );

    test(
      'NativeMemory encodes UTF-8 and UTF-16 strings accurately and strips embedded NULs',
      () {
        const sample = 'Desktop\u0000 Open \u25CF';
        final utf8Bytes = NativeMemory.withUtf8CString(sample, (cstr) {
          final u8 = cstr.cast<ffi.Uint8>();
          final out = <int>[];
          var i = 0;
          while (u8[i] != 0) {
            out.add(u8[i]);
            i++;
          }
          return out;
        });
        expect(utf8Bytes, isNot(contains(0)));
        // 'Desktop Open \u25CF' in UTF-8 is 16 bytes (13 ASCII + 3-byte U+25CF)
        expect(utf8Bytes.length, equals(16));

        final utf16Units = NativeMemory.withUtf16WString(sample, (wstr) {
          final out = <int>[];
          var i = 0;
          while (wstr[i] != 0) {
            out.add(wstr[i]);
            i++;
          }
          return out;
        });
        expect(String.fromCharCodes(utf16Units), equals('Desktop Open \u25CF'));
      },
    );

    test(
      'NativeCoreDiagnostics.onError captures listener exceptions without crashing emit loop',
      () {
        final captured = <String>[];
        NativeCoreDiagnostics.onError = (op, error, _) {
          captured.add('$op:$error');
        };
        addTearDown(() => NativeCoreDiagnostics.onError = null);

        final window = Window.fakeForTesting();
        var secondCalled = false;
        window
          ..addListener((_) => throw StateError('boom'))
          ..addListener((_) => secondCalled = true)
          ..maximize();

        expect(secondCalled, isTrue);
        expect(captured, hasLength(1));
        expect(captured.single, contains('Window.listener:Bad state: boom'));
        window.dispose();
      },
    );

    test(
      'shouldForwardAppExitToWindowClose isolates Windows WM_CLOSE from macOS/Linux app termination',
      () async {
        expect(
          shouldForwardAppExitToWindowClose(
            isWindows: true,
            isMacOS: false,
            isLinux: false,
          ),
          isTrue,
        );
        expect(
          shouldForwardAppExitToWindowClose(
            isWindows: false,
            isMacOS: true,
            isLinux: false,
          ),
          isFalse,
        );
        expect(
          shouldForwardAppExitToWindowClose(
            isWindows: false,
            isMacOS: false,
            isLinux: true,
          ),
          isFalse,
        );

        final window = Window.fakeForTesting();
        window.addListener((event) {
          if (event is WindowCloseRequestedEvent) {
            event.request.cancel();
          }
        });
        final response = await window.didRequestAppExit();
        expect(
          response,
          Platform.isWindows ? AppExitResponse.cancel : AppExitResponse.exit,
        );
        window.dispose();
      },
    );
  });
}
