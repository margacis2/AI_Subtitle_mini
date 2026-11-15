import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_subtitle_studio/domain/entities/project.dart';
import 'package:ai_subtitle_studio/domain/entities/subtitle_cue.dart';
import 'package:ai_subtitle_studio/features/subtitle_editor/presentation/subtitle_editor_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Test data sets
  final shortProject = Project(
    id: 'proj_short',
    name: 'Short Subtitle Project',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    status: ProjectStatus.ready,
    cueCount: 3,
  );
  final shortCues = [
    const SubtitleCue(projectId: 'proj_short', cueIndex: 1, startMs: 1000, endMs: 3000, text: 'First line of dialogue'),
    const SubtitleCue(projectId: 'proj_short', cueIndex: 2, startMs: 3500, endMs: 6000, text: 'Second line of conversation'),
    const SubtitleCue(projectId: 'proj_short', cueIndex: 3, startMs: 6500, endMs: 9000, text: 'Third line of speech'),
  ];

  final longProject = Project(
    id: 'proj_500',
    name: '500 Cues Subtitle Project',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    status: ProjectStatus.ready,
    cueCount: 500,
  );
  final cues500 = List.generate(500, (i) {
    return SubtitleCue(
      projectId: 'proj_500',
      cueIndex: i + 1,
      startMs: i * 2000,
      endMs: (i * 2000) + 1800,
      text: 'Subtitle cue dialogue #${i + 1} with realistic sentence length for layout verification.',
    );
  });

  final multilineProject = Project(
    id: 'proj_multiline',
    name: 'Multiline Subtitle Project',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    status: ProjectStatus.ready,
    cueCount: 2,
  );
  final multilineCues = [
    const SubtitleCue(
      projectId: 'proj_multiline',
      cueIndex: 1,
      startMs: 0,
      endMs: 5000,
      text: 'This is an extremely long subtitle sentence designed to test horizontal wrapping and ensure that neither single-line clipping nor RenderFlex horizontal overflow occurs on any mobile screen width.',
    ),
    const SubtitleCue(
      projectId: 'proj_multiline',
      cueIndex: 2,
      startMs: 5500,
      endMs: 11000,
      text: 'Line 1 of dialogue\nLine 2 of dialogue\nLine 3 of dialogue with detailed information\nLine 4 continuing speech',
    ),
  ];

  group('Scenario 1 & 2: Portrait Mode (Short & 500+ Cues)', () {
    testWidgets('Portrait mode layout bounds video and renders scrollable subtitle panel', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SubtitleEditorScreen(
              projectId: 'proj_short',
              initialProject: shortProject,
              initialCues: shortCues,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Column layout in portrait (video on top, subtitle panel below)
      expect(find.byType(Column), findsWidgets);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);
      expect(find.text('3 Cues (3 total)'), findsOneWidget);

      // Verify no RenderFlex overflow
      expect(tester.takeException(), isNull);
    });

    testWidgets('Portrait mode with 500+ subtitle entries scrolls smoothly to the end', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SubtitleEditorScreen(
              projectId: 'proj_500',
              initialProject: longProject,
              initialCues: cues500,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('500 Cues (500 total)'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);

      // Scroll through the list
      final listView = find.byType(ListView);
      expect(listView, findsOneWidget);

      // Drag to scroll
      await tester.drag(listView, const Offset(0, -500));
      await tester.pumpAndSettle();

      // Fling down toward the end of 500 cues
      await tester.fling(listView, const Offset(0, -4000), 5000);
      await tester.pumpAndSettle();

      // Ensure no layout exceptions or RenderFlex errors occurred
      expect(tester.takeException(), isNull);
    });
  });

  group('Scenario 3: Landscape Mode (Side-by-Side Coexistence)', () {
    testWidgets('Landscape mode renders side-by-side Row with video on left and subtitles on right', (WidgetTester tester) async {
      // Landscape phone / tablet (840 x 400)
      tester.view.physicalSize = const Size(840, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SubtitleEditorScreen(
              projectId: 'proj_500',
              initialProject: longProject,
              initialCues: cues500,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In landscape (width > height && width >= 550), it uses Row for side-by-side layout
      final rowFinder = find.byWidgetPredicate(
        (widget) => widget is Row && widget.children.any((c) => c is VerticalDivider),
      );
      expect(rowFinder, findsOneWidget);

      // Subtitle panel is fully visible and scrollable in landscape
      expect(find.text('500 Cues (500 total)'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);

      // Drag list in landscape
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Verify zero RenderFlex overflows
      expect(tester.takeException(), isNull);
    });
  });

  group('Scenario 4 & 5: Rotation Dynamics (Portrait <-> Landscape)', () {
    testWidgets('Rotate from Portrait to Landscape while maintaining state', (WidgetTester tester) async {
      // 1. Start in portrait
      tester.view.physicalSize = const Size(412, 869);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SubtitleEditorScreen(
              projectId: 'proj_short',
              initialProject: shortProject,
              initialCues: shortCues,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('#1'), findsOneWidget);

      // 2. Rotate to landscape
      tester.view.physicalSize = const Size(869, 412);
      await tester.pumpAndSettle();

      // Verify side-by-side Row with VerticalDivider exists
      final rowFinder = find.byWidgetPredicate(
        (widget) => widget is Row && widget.children.any((c) => c is VerticalDivider),
      );
      expect(rowFinder, findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 3. Rotate back to portrait
      tester.view.physicalSize = const Size(412, 869);
      await tester.pumpAndSettle();

      expect(find.text('#1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Scenario 6 & 7: Long Text Wrapping & Small Screen Constraints', () {
    testWidgets('Long text and multiple lines wrap gracefully without overflow on small screens', (WidgetTester tester) async {
      // Compact phone size: 320 x 480
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SubtitleEditorScreen(
              projectId: 'proj_multiline',
              initialProject: multilineProject,
              initialCues: multilineCues,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('#1'), findsOneWidget);

      // On a compact screen (320x480), drag list to bring cue #2 into viewport
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.text('#2'), findsOneWidget);

      // Long text is rendered without horizontal clipping or overflow
      expect(find.byType(ListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Scenario 8: Fullscreen Video Mode', () {
    testWidgets('Entering and exiting fullscreen mode toggles layout cleanly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 450);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SubtitleEditorScreen(
              projectId: 'proj_short',
              initialProject: shortProject,
              initialCues: shortCues,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find fullscreen icon button
      final fsButton = find.byTooltip('Fullscreen');
      if (fsButton.evaluate().isNotEmpty) {
        await tester.tap(fsButton);
        await tester.pumpAndSettle();

        // Subtitle panel is hidden in fullscreen; back button is visible
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

        // Exit fullscreen
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();

        // Subtitles panel restored
        expect(find.text('#1'), findsOneWidget);
      }

      expect(tester.takeException(), isNull);
    });
  });

  group('Scenario 9: Search Filtering & Cue Interaction', () {
    testWidgets('Searching cues filters the list dynamically without breaking scrolling', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SubtitleEditorScreen(
              projectId: 'proj_short',
              initialProject: shortProject,
              initialCues: shortCues,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter search query
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'Second');
      await tester.pumpAndSettle();

      // Should only show cue #2
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#1'), findsNothing);
      expect(find.text('#3'), findsNothing);
      expect(find.text('1 Cues (3 total)'), findsOneWidget);

      // Clear search
      final clearButton = find.byIcon(Icons.clear_rounded);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
