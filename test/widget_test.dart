import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stream_app/main.dart';

void main() {
  testWidgets('Bottom navigation and search screen smoke test', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsWidgets);
    expect(find.textContaining('TMDB'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
