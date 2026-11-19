import 'package:flutter/widgets.dart';
import 'package:native_core/native_core.dart';

/// Entrypoint for the `native_core` desktop window and display example.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final window = mainWindow;
  if (window != null) {
    if (!hideLinuxNativeTitleBar(window)) {
      window.titleBarStyle = TitleBarStyle.hidden;
    }
    window
      ..minimumSize = const NativeSize(640, 420)
      ..backgroundColor = const NativeColor(0xFF0F172A)
      ..title = 'native_core Example'
      ..setSize(const NativeSize(960, 620))
      ..center()
      ..show()
      ..focus();
  }

  runApp(const NativeCoreExampleApp());
}

/// Pure `widgets.dart` demonstration of `native_core` window and display APIs.
class NativeCoreExampleApp extends StatefulWidget {
  /// Creates a [NativeCoreExampleApp].
  const NativeCoreExampleApp({super.key});

  @override
  State<NativeCoreExampleApp> createState() => _NativeCoreExampleAppState();
}

class _NativeCoreExampleAppState extends State<NativeCoreExampleApp> {
  final List<String> _events = <String>[];
  ListenerId? _listenerId;

  @override
  void initState() {
    super.initState();
    _listenerId = mainWindow?.addListener((event) {
      setState(() {
        _events.insert(0, event.runtimeType.toString());
        if (_events.length > 8) _events.removeLast();
      });
    });
  }

  @override
  void dispose() {
    final id = _listenerId;
    if (id != null) {
      mainWindow?.removeListener(id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displays = DisplayManager.instance.getAll();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF0F172A),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'native_core — Desktop Window & Display Inspector',
                style: TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _ActionPill(
                    label: 'Maximize',
                    onTap: () => mainWindow?.maximize(),
                  ),
                  _ActionPill(
                    label: 'Unmaximize',
                    onTap: () => mainWindow?.unmaximize(),
                  ),
                  _ActionPill(
                    label: 'Center 960×620',
                    onTap: () {
                      mainWindow
                        ?..setSize(const NativeSize(960, 620))
                        ..center();
                    },
                  ),
                  _ActionPill(
                    label: 'Quit',
                    onTap: () => Application.instance.quit(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Connected Displays (${displays.length}):',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final d in displays)
                Text(
                  'Display #${d.id}: bounds=${d.bounds.width.round()}×${d.bounds.height.round()} '
                  'workArea=${d.workArea.width.round()}×${d.workArea.height.round()} '
                  'scale=${d.scaleFactor.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 13,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Recent Window Events: ${_events.isEmpty ? "none" : _events.join(", ")}',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}
