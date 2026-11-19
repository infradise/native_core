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
  });
}
