import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:stream_app/main.dart';

void main() {
  setUpAll(() async {
    final tempDir = Directory.systemTemp.createTempSync('stream_app_test_');
    Hive.init(tempDir.path);
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
