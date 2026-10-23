import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/main.dart';

void main() {
  testWidgets('BlockBlastApp launches successfully with arcade UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BlockBlastApp());
    // Finds initial score '0'
    expect(find.text('0'), findsNWidgets(2)); // Current score 0, Best score 0
  });

  testWidgets('Toggling AI autoplay from settings does not crash', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BlockBlastApp());

    // AI autoplay now lives behind the gear/settings sheet, not a header button.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final aiSwitch = find.text('AI autoplay');
    expect(aiSwitch, findsOneWidget);
    await tester.tap(aiSwitch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Toggle off again via the same settings sheet. AI mode's autoplay loop
    // keeps scheduling retry timers while on, so pumpAndSettle would hang —
    // use a bounded pump instead, same as above.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('AI autoplay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Tapping hint from settings highlights a recommendation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BlockBlastApp());

    // Hint now lives behind the gear/settings sheet, not a header button —
    // keeps the default screen's header matching the reference game (just
    // crown+score and a gear icon).
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hint'), findsWidgets);
    await tester.tap(find.text('Hint').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify hint badge appeared on the board.
    expect(find.text('HINT'), findsOneWidget);

    // Tapping again from settings dismisses the hint.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Hint').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('HINT'), findsNothing);
  });

  testWidgets('Toggling edit board from settings cycles a dock piece', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BlockBlastApp());

    // Edit mode now lives behind the gear/settings sheet too.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final editSwitch = find.text('Edit board');
    expect(editSwitch, findsOneWidget);
    await tester.tap(editSwitch);
    await tester.pump();
    expect(find.text('CYCLE'), findsNWidgets(3));

    // Tap first dock piece to cycle shape.
    await tester.tap(find.text('CYCLE').first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Turn edit mode back off via settings.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Edit board'));
    await tester.pump();
    expect(find.text('CYCLE'), findsNothing);
  });

  testWidgets('Persisted high score and game state are restored on startup', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'high_score': 99999,
      'score': 1234,
      'board': '255',
      'dock': ['0', '1', '2'],
      'combo': 3,
      'is_game_over': false,
    });

    await tester.pumpWidget(const BlockBlastApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('99999'), findsOneWidget); // Restored best score
    expect(find.text('1234'), findsOneWidget); // Restored current score
  });

  testWidgets('Top action buttons Hint and Edit work directly from header', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BlockBlastApp());

    // Tap Hint directly on header
    final hintBtn = find.byTooltip('Hint');
    expect(hintBtn, findsOneWidget);
    await tester.tap(hintBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HINT'), findsOneWidget);

    // Dismiss hint
    await tester.tap(hintBtn);
    await tester.pump();
    expect(find.text('HINT'), findsNothing);

    // Tap Edit directly on header
    final editBtn = find.byTooltip('Edit Mode');
    expect(editBtn, findsOneWidget);
    await tester.tap(editBtn);
    await tester.pump();
    expect(find.text('CYCLE'), findsNWidgets(3));

    // Turn off edit
    await tester.tap(editBtn);
    await tester.pump();
    expect(find.text('CYCLE'), findsNothing);
  });
}
