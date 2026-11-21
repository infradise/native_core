/// Internal test-only barrel exposing platform algorithms and live FFI probes
/// for `test/` without polluting the public `pub.dev` API.
library;

export '../platform/linux/linux_headerbar_grab.dart'
    show
        attachLinuxEventPointerDevice,
        debugProbeLinuxSynthesizedButtonReleaseEvent;
export '../platform/linux/linux_window_adapter.dart'
    show
        LinuxPresentAction,
        LinuxSignalLifecycle,
        resolveLinuxPresentAction,
        selectPrimaryLinuxToplevel;
export '../platform/macos/macos_appkit_bindings.dart'
    show
        debugHasMacOSAppLifecycleObserverClass,
        kNSApplicationActivationPolicyAccessory,
        kNSApplicationActivationPolicyProhibited,
        kNSApplicationActivationPolicyRegular;
export '../platform/macos/macos_window_adapter.dart'
    show
        MacOSActivationPlan,
        MacOSActivationPolicyProbeResult,
        debugRunMacOSStatusItemActivationPolicyProbe,
        resolveMacOSActivationPlan,
        shouldRestoreMacOSActivationPolicyOnShow,
        shouldSwitchMacOSActivationPolicyOnHide;
export '../platform/macos/macos_window_delegate.dart'
    show
        MacOSWindowCloseProbeResult,
        MacOSWindowDetachProbeResult,
        debugHasMacOSReplaceMethodSymbol,
        debugRunMacOSWindowDetachForAppExitProbe,
        debugRunMacOSWindowShouldCloseProbe;
export '../platform/unix_single_instance.dart'
    show UnixSingleInstanceCoordinator, resolveUnixSingleInstanceSocketPath;
export '../platform/windows/windows_frame_subclass.dart'
    show
        Win32EraseBkgndDecision,
        Win32FramelessProbeResult,
        Win32InitialShowInterceptDecision,
        computeWin32MaximizedClientRect,
        debugRunWin32FramelessProbe,
        decodeWin32SignedX,
        decodeWin32SignedY,
        hitTestWin32ResizeBorder,
        resolveWin32EraseBkgndAction,
        resolveWin32WindowPosShowIntercept;
export '../platform/windows/windows_single_instance.dart'
    show
        WindowsSingleInstanceCoordinator,
        debugCanAcquireWindowsSingleInstanceMutex,
        debugWin32CopyDataStructSize;
export '../single_instance.dart'
    show
        SingleInstanceCoordinator,
        computeSingleInstanceHash,
        sanitizeSingleInstanceToken;
export '../window.dart' show shouldForwardAppExitToWindowClose;
