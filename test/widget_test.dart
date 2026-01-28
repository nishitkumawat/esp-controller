// import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:machmate_controller/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SwiftControllerApp());

    // Verify that main UI elements exist (example: the "Enter Device ID" TextField)
    expect(find.text('Enter Device ID'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('STOP'), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);
  });
}
-