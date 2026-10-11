// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:silent_help/main.dart';

void main() {
  testWidgets('Calculator smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SilentHelpApp());

    // Verify that calculator starts with 0
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Calculator'), findsOneWidget);

    // Tap the '1' button and verify display updates
    await tester.tap(find.text('1'));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });
}
