import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_core/native_core.dart';
// ignore: implementation_imports
import 'package:native_core/src/testing/native_core_testing.dart';

void main() {
  group('macOS AppKit window activation and display metrics', () {
    test(
      'resolveMacOSActivationPlan invokes -[NSApplication activate] on macOS 14-27 even when deprecated activateIgnoringOtherApps: exists',
      () {
        final modernMacPlan = resolveMacOSActivationPlan(
          hasActivateSelector: true,
          hasActivateIgnoringSelector: true,
        );
        expect(modernMacPlan.callActivate, isTrue);
        expect(modernMacPlan.callActivateIgnoringOtherApps, isTrue);

        final venturaPlan = resolveMacOSActivationPlan(
          hasActivateSelector: false,
          hasActivateIgnoringSelector: true,
        );
        expect(venturaPlan.callActivate, isFalse);
        expect(venturaPlan.callActivateIgnoringOtherApps, isTrue);
      },
    );

    test(
      'MacOSAppKitBindings loads libobjc.A.dylib including class_replaceMethod on macOS',
      () {
        if (!Platform.isMacOS) return;
        expect(debugHasMacOSReplaceMethodSymbol(), isTrue);
      },
    );

    test(
      'DisplayManager.instance.getAll returns valid display metrics on macOS',
      () {
        if (!Platform.isMacOS) return;
        final displays = DisplayManager.instance.getAll();
        expect(displays, isNotEmpty);
        expect(displays.first.bounds.width, greaterThan(0));
        expect(displays.first.bounds.height, greaterThan(0));
        expect(displays.first.workArea.width, greaterThan(0));
        expect(displays.first.workArea.height, greaterThan(0));
      },
    );

    test(
      'shouldSwitchMacOSActivationPolicyOnHide switches to Accessory only when a status item is active and no other app window is visible',
      () {
        expect(
          shouldSwitchMacOSActivationPolicyOnHide(
            hasActiveStatusItem: true,
            hasOtherVisibleAppWindow: false,
            isVisibleInTaskbar: true,
          ),
          isTrue,
        );
        expect(
          shouldSwitchMacOSActivationPolicyOnHide(
            hasActiveStatusItem: false,
            hasOtherVisibleAppWindow: false,
            isVisibleInTaskbar: true,
          ),
          isFalse,
        );
        expect(
          shouldSwitchMacOSActivationPolicyOnHide(
            hasActiveStatusItem: true,
            hasOtherVisibleAppWindow: true,
            isVisibleInTaskbar: true,
          ),
          isFalse,
        );
        expect(
          shouldSwitchMacOSActivationPolicyOnHide(
            hasActiveStatusItem: true,
            hasOtherVisibleAppWindow: false,
            isVisibleInTaskbar: false,
          ),
          isFalse,
        );

        expect(
          shouldRestoreMacOSActivationPolicyOnShow(
            switchedToAccessoryOnHide: true,
            isVisibleInTaskbar: true,
            currentActivationPolicy: kNSApplicationActivationPolicyAccessory,
          ),
          isTrue,
        );
        expect(
          shouldRestoreMacOSActivationPolicyOnShow(
            switchedToAccessoryOnHide: false,
            isVisibleInTaskbar: false,
            currentActivationPolicy: kNSApplicationActivationPolicyAccessory,
          ),
          isFalse,
        );
        expect(
          shouldRestoreMacOSActivationPolicyOnShow(
            switchedToAccessoryOnHide: false,
            isVisibleInTaskbar: true,
            currentActivationPolicy: kNSApplicationActivationPolicyRegular,
          ),
          isFalse,
        );
      },
    );

    test(
      'live macOS NativeCoreWindowDelegate dispatches windowShouldClose: and NSWindowDidBecomeKeyNotification via objc_msgSend',
      () {
        if (!Platform.isMacOS) return;
        final probe = debugRunMacOSWindowShouldCloseProbe();
        expect(probe, isNotNull);
        expect(probe!.cancelReturnedFalse, isTrue);
        expect(probe.allowReturnedTrue, isTrue);
        expect(probe.becameKeyDispatched, isTrue);
      },
    );

    test(
      'live macOS status item detection and NSApplication activation policy transitions succeed',
      () {
        if (!Platform.isMacOS) return;
        final probe = debugRunMacOSStatusItemActivationPolicyProbe();
        expect(probe, isNotNull);
        expect(probe!.detectedStatusBarWindowWhileActive, isTrue);
        expect(probe.switchedToAccessoryPolicy, isTrue);
        expect(probe.restoredRegularPolicy, isTrue);
        expect(probe.clearedStatusBarWindowAfterRemove, isTrue);
      },
    );

    test(
      'live macOS NSApplicationWillTerminateNotification observer dispatches cleanup callbacks',
      () {
        if (!Platform.isMacOS) return;
        expect(debugRunMacOSWillTerminateObserverProbe(), isTrue);
      },
    );
  });
}
