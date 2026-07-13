import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/l10n/app_localizations.dart';
import 'package:three_style_trainer/practice_type.dart';
import 'package:three_style_trainer/screens/session_summary_screen.dart';
import 'package:three_style_trainer/theme/app_palette.dart';
import 'package:three_style_trainer/theme/theme_scope.dart';
import 'package:three_style_trainer/widgets/recording_dot.dart';

// Renders the summary in both modes and on a narrow screen to catch layout
// overflow (RenderFlex) and the bar/tick rendering. Not a golden test — just
// that it builds and lays out cleanly.
Widget _host(Widget child, AppPalette palette) => ThemeScope(
      palette: palette,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(palette),
        home: child,
      ),
    );

// Modifiable list — the screen sorts it in place (production passes a copy).
List<AlgTime> _sampleTimes() => [
      const AlgTime(1, 770, Alg("BA"), timestamp: 1),
      const AlgTime(2, 790, Alg("XT"), timestamp: 2),
      const AlgTime(3, 800, Alg("AG"), timestamp: 3),
      const AlgTime(4, 810, Alg("UF-DR"), timestamp: 4), // long 2-flip name
      const AlgTime(5, 820, Alg("BL"), timestamp: 5),
      const AlgTime(6, 910, Alg("VU"), timestamp: 6),
    ];

// Same cases but every solve carries a recognition/execution split, as a
// smart-cube session would.
List<AlgTime> _splitTimes() => [
      const AlgTime(1, 770, Alg("BA"), timestamp: 1, recognitionMs: 300),
      const AlgTime(2, 790, Alg("XT"), timestamp: 2, recognitionMs: 260),
      const AlgTime(3, 800, Alg("AG"), timestamp: 3, recognitionMs: 410),
      const AlgTime(4, 810, Alg("BL"), timestamp: 4, recognitionMs: 350),
      const AlgTime(5, 910, Alg("VU"), timestamp: 5, recognitionMs: 500),
    ];

// A wrong-pair execution, a manual requeue, and a case botched twice — as a
// cube-driven run logs them.
List<AlgMistake> _sampleMistakes() => [
      const AlgMistake(1, Alg("AG"), AlgMistakeKind.wrongCase, executed: "GA"),
      const AlgMistake(2, Alg("VU"), AlgMistakeKind.requeued),
      const AlgMistake(3, Alg("AG"), AlgMistakeKind.requeued),
    ];

void main() {
  testWidgets('errors section groups the mistakes by case', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _sampleTimes(),
        mistakes: _sampleMistakes(),
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 12000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Requeued'), 120);
    expect(find.text('ERRORS (3)'), findsOneWidget);
    // AG went wrong twice: one row, both attempts, a (2) marker.
    expect(find.text('Executed GA · Requeued'), findsOneWidget);
    expect(find.text('(2)'), findsOneWidget);
    // VU was requeued once and keeps its own row.
    expect(find.text('Requeued'), findsOneWidget);
    // Counted on their own tile, and excluded from the times' stats.
    expect(find.text('MISTAKES'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
  });

  testWidgets('no mistakes: no errors section or tile', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _sampleTimes(),
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 12000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('MISTAKES'), findsNothing);
    expect(find.text('ERRORS (0)'), findsNothing);
  });

  for (final palette in [AppPalette.slate, AppPalette.cubeFace]) {
    testWidgets('renders time-race summary (${palette.id.name})',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640)); // narrow
      await tester.pumpWidget(_host(
        SessionSummaryScreen(
          algTimes: _sampleTimes(),
          algType: AlgType.Corner,
          targetTime: 0.85,
          practiceType: PracticeType.timeRace,
          totalTimeMs: 6000,
        ),
        palette,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('VU'), findsOneWidget);
    });

    testWidgets('renders sets summary (${palette.id.name})', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      await tester.pumpWidget(_host(
        SessionSummaryScreen(
          algTimes: _sampleTimes(),
          algType: AlgType.Corner,
          targetTime: 0.85,
          practiceType: PracticeType.sets,
          totalTimeMs: 12000,
        ),
        palette,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renders recognition/execution split columns cleanly',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _splitTimes(),
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.timeRace,
        totalTimeMs: 4080,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The split header labels and every alg render.
    expect(find.text('RECOG'), findsOneWidget);
    expect(find.text('EXEC'), findsOneWidget);
    expect(find.text('VU'), findsOneWidget);
    // Too narrow for the pills alongside the columns, so they're dropped.
    expect(find.text('SLOWEST'), findsNothing);
  });

  testWidgets('split columns keep the pills on a wide screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 700));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _splitTimes(),
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.timeRace,
        totalTimeMs: 4080,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Both the split columns and the fastest/slowest pills fit here.
    expect(find.text('RECOG'), findsOneWidget);
    expect(find.text('SLOWEST'), findsOneWidget);
    expect(find.text('FASTEST'), findsOneWidget);
  });

  testWidgets('defaults to occurrence order, not fastest time', (tester) async {
    // Occurrence order AA, BB, CC; fastest is CC (0.50).
    final times = [
      const AlgTime(1, 800, Alg('AA'), timestamp: 1),
      const AlgTime(2, 900, Alg('BB'), timestamp: 2),
      const AlgTime(3, 500, Alg('CC'), timestamp: 3),
    ];
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: times,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.timeRace,
        totalTimeMs: 2200,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();

    // Top row is the first case (AA), not the fastest (CC).
    final yAA = tester.getTopLeft(find.text('AA')).dy;
    final yCC = tester.getTopLeft(find.text('CC')).dy;
    expect(yAA, lessThan(yCC));
  });

  testWidgets('non-recording: no delete button, swipe explains why',
      (tester) async {
    // No onDeleteFromDb callback -> not a recording run.
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _sampleTimes(),
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.timeRace,
        totalTimeMs: 6000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    expect(find.byType(RecordingDot), findsNothing);

    await tester.drag(find.text('VU'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining("wasn't recorded"), findsOneWidget);
  });

  testWidgets('recording: swipe reveals delete, removes DB row, undo restores',
      (tester) async {
    final times = [const AlgTime(1, 800, Alg('BL'), timestamp: 111)];
    final deleted = <AlgTime>[];
    final restored = <AlgTime>[];
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: times,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.timeRace,
        totalTimeMs: 800,
        onDeleteFromDb: deleted.add,
        onRestoreToDb: restored.add,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(RecordingDot), findsOneWidget);

    // Swiping does not delete on its own — it reveals the button.
    await tester.drag(find.text('BL'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(find.text('BL'), findsOneWidget);
    expect(deleted, isEmpty);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('BL'), findsNothing);
    expect(deleted, hasLength(1));
    expect(find.textContaining('Deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('BL'), findsOneWidget);
    expect(restored, hasLength(1));
  });

  testWidgets('recording: a short swipe still opens (no fold-back)',
      (tester) async {
    final times = [const AlgTime(1, 800, Alg('BL'), timestamp: 111)];
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: times,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.timeRace,
        totalTimeMs: 800,
        onDeleteFromDb: (_) {},
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();

    // A quick flick that doesn't travel the full reveal width should still open
    // the row rather than fold back.
    await tester.fling(find.text('BL'), const Offset(-60, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('recording: swiping a second row collapses the first',
      (tester) async {
    final deleted = <AlgTime>[];
    final times = [
      const AlgTime(1, 800, Alg('AA'), timestamp: 1),
      const AlgTime(2, 900, Alg('BB'), timestamp: 2),
    ];
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: times,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.timeRace,
        totalTimeMs: 1700,
        onDeleteFromDb: deleted.add,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();

    // Open the first row.
    await tester.drag(find.text('AA'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);

    // Swiping the second row must leave exactly one Delete button (the first
    // row collapses), and the open one must be the second row.
    await tester.drag(find.text('BB'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, hasLength(1));
    expect(deleted.single.alg.name, 'BB');
  });

  testWidgets('recording: dragging a second row never shows two Delete buttons',
      (tester) async {
    final times = [
      const AlgTime(1, 800, Alg('AA'), timestamp: 1),
      const AlgTime(2, 900, Alg('BB'), timestamp: 2),
    ];
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: times,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.timeRace,
        totalTimeMs: 1700,
        onDeleteFromDb: (_) {},
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();

    // Open the first row, then slowly drag the second one open frame by frame.
    // At no point during the hand-off may both Delete buttons be on screen.
    await tester.drag(find.text('AA'), const Offset(-150, 0));
    await tester.pumpAndSettle();

    final g = await tester.startGesture(tester.getCenter(find.text('BB')));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Delete').evaluate().length, lessThanOrEqualTo(1));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('sets: editing the target updates the summary', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final times = [const AlgTime(1, 800, Alg('BA'), timestamp: 1)];
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: times,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 800,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('0.85'), findsWidgets);

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '1.20');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Target line reflects the new value; the old one is gone.
    expect(find.textContaining('1.20'), findsWidgets);
    expect(find.textContaining('0.85'), findsNothing);
    expect(SharedPreferences.getInstance()
        .then((p) => p.getDouble('target_time')), completion(1.2));
  });
}
