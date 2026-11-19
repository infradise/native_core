import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_core/native_core.dart';
// ignore: implementation_imports
import 'package:native_core/src/testing/native_core_testing.dart';

void main() {
  group('Linux GTK3 window resolution and GSignal lifecycle', () {
    test(
      'selectPrimaryLinuxToplevel skips prepended GTK_WINDOW_POPUP tooltips and resolves hidden registered main window',
      () {
        const tooltipPopup = 'gtk-tooltip-popup';
        const menuPopup = 'gtk-menu-popup';
        const hiddenOtherToplevel = 'hidden-secondary-toplevel';
        const hiddenMainWindow = 'hidden-main-application-window';

        final selectedWhileHidden = selectPrimaryLinuxToplevel<String>(
          candidates: const <String>[
            tooltipPopup,
            menuPopup,
            hiddenOtherToplevel,
            hiddenMainWindow,
          ],
          isToplevelType: (w) => !w.endsWith('-popup'),
          isAlive: (_) => true,
          isRealized: (_) => true,
          isVisible: (_) => false,
          isActive: (_) => false,
          isPreviouslyRegistered: (w) => w == hiddenMainWindow,
        );
        expect(selectedWhileHidden, equals(hiddenMainWindow));

        final selectedWhileVisible = selectPrimaryLinuxToplevel<String>(
          candidates: const <String>[
            tooltipPopup,
            hiddenOtherToplevel,
            hiddenMainWindow,
          ],
          isToplevelType: (w) => !w.endsWith('-popup'),
          isAlive: (_) => true,
          isRealized: (_) => true,
          isVisible: (w) => w == hiddenMainWindow || w == tooltipPopup,
          isActive: (w) => w == hiddenMainWindow,
          isPreviouslyRegistered: (w) => w == hiddenMainWindow,
        );
        expect(selectedWhileVisible, equals(hiddenMainWindow));
      },
    );

    test(
      'LinuxSignalLifecycle disconnects GObject handlers strictly BEFORE closing NativeCallables while widget is alive',
      () {
        final sequence = <String>[];
        final lifecycle = LinuxSignalLifecycle(
          disconnectSignal: (id) => sequence.add('disconnect:$id'),
          closeCallables: () => sequence.add('closeCallables'),
        )..recordConnected(deleteEventId: 41, destroyEventId: 42);

        lifecycle.dispose(isWidgetAlive: true);
        // Idempotent second dispose call must be a no-op.
        lifecycle.dispose(isWidgetAlive: true);

        expect(
          sequence,
          equals(<String>['disconnect:41', 'disconnect:42', 'closeCallables']),
        );
      },
    );

    test(
      'LinuxSignalLifecycle skips g_signal_handler_disconnect after GTK destroy signal fires',
      () {
        final sequence = <String>[];
        final lifecycle = LinuxSignalLifecycle(
          disconnectSignal: (id) => sequence.add('disconnect:$id'),
          closeCallables: () => sequence.add('closeCallables'),
        )..recordConnected(deleteEventId: 77, destroyEventId: 78);

        lifecycle.handleWidgetDestroyed();
        lifecycle.dispose(isWidgetAlive: false);

        expect(sequence, equals(<String>['closeCallables']));
      },
    );

    test(
      'resolveLinuxPresentAction prevents unmapped Wayland present_with_time(0) while preserving X11 and mapped focus',
      () {
        // Wayland startup (before first-frame map): show() uses widgetShowOnly,
        // immediate synchronous focus() becomes noop so Mutter never emits
        // an unauthenticated "<App> is ready" attention notification.
        expect(
          resolveLinuxPresentAction(
            isShow: true,
            isX11: false,
            isVisible: false,
            isMapped: false,
          ),
          LinuxPresentAction.widgetShowOnly,
        );
        expect(
          resolveLinuxPresentAction(
            isShow: false,
            isX11: false,
            isVisible: true,
            isMapped: false,
          ),
          LinuxPresentAction.noop,
        );
        // Wayland focus() on a hidden unmapped window still shows it.
        expect(
          resolveLinuxPresentAction(
            isShow: false,
            isX11: false,
            isVisible: false,
            isMapped: false,
          ),
          LinuxPresentAction.widgetShowOnly,
        );
        // Wayland already-mapped window uses gtk_window_present_with_time.
        expect(
          resolveLinuxPresentAction(
            isShow: true,
            isX11: false,
            isVisible: true,
            isMapped: true,
          ),
          LinuxPresentAction.presentWithTime,
        );
        expect(
          resolveLinuxPresentAction(
            isShow: false,
            isX11: false,
            isVisible: true,
            isMapped: true,
          ),
          LinuxPresentAction.presentWithTime,
        );
        // X11 hidden show() maps via widgetShowOnly; focus() presents with
        // fresh X11 server timestamp.
        expect(
          resolveLinuxPresentAction(
            isShow: true,
            isX11: true,
            isVisible: false,
            isMapped: false,
          ),
          LinuxPresentAction.widgetShowOnly,
        );
        expect(
          resolveLinuxPresentAction(
            isShow: false,
            isX11: true,
            isVisible: true,
            isMapped: false,
          ),
          LinuxPresentAction.presentWithTime,
        );
      },
    );

    test('Linux GTK helpers are safe no-ops on non-Linux hosts', () {
      if (Platform.isLinux) return;
      final fake = Window.fakeForTesting();
      expect(hideLinuxNativeTitleBar(fake), isFalse);
      expect(() => releaseLinuxMouseButtonAfterGrab(fake), returnsNormally);
      fake.dispose();
    });
  });
}
