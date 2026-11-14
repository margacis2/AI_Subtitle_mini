import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_subtitle_studio/features/home/presentation/home_screen.dart';

void main() {
  testWidgets('HomeScreen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('AI Subtitle Studio'), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
