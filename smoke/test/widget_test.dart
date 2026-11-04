import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke/counter.dart';

void main() {
  testWidgets('increments the counter', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Counter()));
    expect(find.text('Count: 0'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(find.text('Count: 1'), findsOneWidget);
  });

  testWidgets('matches the golden file', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Counter()));
    await expectLater(
      find.byType(Counter),
      matchesGoldenFile('goldens/counter.png'),
    );
  });
}
