import 'package:flutter_test/flutter_test.dart';
import 'package:native_core_example/main.dart';

void main() {
  testWidgets('NativeCoreExampleApp renders header, controls, and displays', (
    tester,
  ) async {
    await tester.pumpWidget(const NativeCoreExampleApp());

    expect(
      find.text('native_core — Desktop Window & Display Inspector'),
      findsOneWidget,
    );
    expect(find.text('Maximize'), findsOneWidget);
    expect(find.text('Unmaximize'), findsOneWidget);
    expect(find.text('Center 960×620'), findsOneWidget);
    expect(find.text('Quit'), findsOneWidget);
    expect(find.textContaining('Connected Displays'), findsOneWidget);
    expect(find.textContaining('Recent Window Events:'), findsOneWidget);
  });
}
