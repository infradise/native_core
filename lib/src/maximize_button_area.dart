import 'package:flutter/widgets.dart';

import 'window.dart';

/// Wraps a custom window maximize button to associate it with its target
/// [Window].
class MaximizeButtonArea extends StatelessWidget {
  /// Creates a [MaximizeButtonArea] for [window] wrapping [child].
  const MaximizeButtonArea({
    super.key,
    required this.window,
    required this.child,
  });

  /// Target desktop [Window] controlled by the wrapped maximize button.
  final Window window;

  /// Maximize/restore button widget rendered inside this area.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
