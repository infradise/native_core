/// Zero-dependency desktop window, display, and application lifecycle
/// primitives for Flutter across Linux (`GTK3`/`Wayland`/`X11`), macOS
/// (`AppKit`), and Windows (`Win32`).
library;

export 'src/application.dart' show Application;
export 'src/diagnostics.dart'
    show NativeCoreDiagnostics, NativeCoreErrorReporter;
export 'src/display_manager.dart' show Display, DisplayManager;
export 'src/main_window.dart' show WindowsMainWindowCache, mainWindow;
export 'src/maximize_button_area.dart' show MaximizeButtonArea;
export 'src/models.dart'
    show
        EventRequest,
        ListenerId,
        NativeColor,
        NativeColorConversionX,
        NativeOffset,
        NativeOffsetConversionX,
        NativeRect,
        NativeRectConversionX,
        NativeSize,
        NativeSizeConversionX,
        TitleBarStyle,
        WindowBlurredEvent,
        WindowCloseRequestedEvent,
        WindowEvent,
        WindowFocusedEvent,
        WindowMaximizedEvent,
        WindowMinimizedEvent,
        WindowMovedEvent,
        WindowResizedEvent,
        WindowRestoredEvent,
        WindowUnmaximizedEvent;
export 'src/platform/linux/linux_headerbar_grab.dart'
    show
        hideLinuxNativeTitleBar,
        releaseLinuxMouseButtonAfterGrab,
        showPlatformWindowSystemMenu,
        startPlatformWindowDragging;
export 'src/platform/windows/windows_window_finder.dart'
    show
        findCurrentProcessFlutterWindowHandle,
        isWindowsNativeWindowAlive,
        kFlutterWin32WindowClassName;
export 'src/single_instance.dart' show InstanceMode, SecondInstancePayload;
export 'src/window.dart' show Window, WindowManager;
