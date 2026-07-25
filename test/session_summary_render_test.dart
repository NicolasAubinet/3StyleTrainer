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

// Cube-driven solves carrying their session-only moves: one reconstructed,
// one raw (parser declined), one press-timed with none.
List<AlgTime> _movesTimes() => [
      const AlgTime(1, 770, Alg("BA"),
          timestamp: 1, recognitionMs: 300, moves: "M U M' U'"),
      const AlgTime(2, 790, Alg("XT"),
          timestamp: 2,
          recognitionMs: 260,
          moves: "R L' U R' L U'",
          movesReconstructed: false),
      const AlgTime(3, 800, Alg("AG"), timestamp: 3),
    ];

// A wrong-pair execution, a manual requeue, and a case botched twice — as a
// cube-driven run logs them.
List<AlgMistake> _sampleMistakes() => [
      const AlgMistake(1, Alg("AG"), AlgMistakeKind.wrongCase,
          executed: "GA", moves: "R U R' U'"),
      const AlgMistake(2, Alg("VU"), AlgMistakeKind.requeued),
      const AlgMistake(3, Alg("AG"), AlgMistakeKind.requeued,
          moves: "L' U2 L F R F' D2"),
    ];

void main() {
  testWidgets('errors section groups the mistakes by case', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _sampleTimes(),
        mistakes: _sampleMistakes(),
        cubeDriven: true,
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
    // Counted as the Solved tile's parenthetical, and left out of the times.
    expect(find.text('SOLVED'), findsOneWidget);
    expect(find.text('6 (3)'), findsOneWidget);
  });

  testWidgets('repeated attempts count cases, not attempts, in Hit target',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        // BA over target then under, as a repeat-until-under-target run
        // produces; XT under on its only attempt.
        algTimes: [
          const AlgTime(1, 1200, Alg("BA"), timestamp: 1),
          const AlgTime(2, 700, Alg("BA"), timestamp: 2),
          const AlgTime(3, 800, Alg("XT"), timestamp: 3),
        ],
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 12000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 3 attempts, but 2 cases — both with a best attempt under target.
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('a recovered case reads as solved from a botched state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _sampleTimes(),
        mistakes: [
          const AlgMistake(1, Alg("VU"), AlgMistakeKind.recovered,
              moves: "R M U2 M' U2")
        ],
        cubeDriven: true,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 12000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Solved from a botched state'), 120);
    expect(find.text('ERRORS (1)'), findsOneWidget);
  });

  testWidgets('a review-mode skip shows the errors section without a cube',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _sampleTimes(),
        mistakes: [const AlgMistake(1, Alg("VU"), AlgMistakeKind.skipped)],
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 12000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Skipped'), 120);
    expect(find.text('ERRORS (1)'), findsOneWidget);
    // The solved tile carries the error parenthetical even with no cube.
    expect(find.text('6 (1)'), findsOneWidget);
  });

  testWidgets('tapping an errored case shows every attempt in full',
      (tester) async {
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

    // The row shows the latest attempt's moves, clipped to one line.
    await tester.scrollUntilVisible(find.text("L' U2 L F R F' D2"), 120);
    await tester.tap(find.text("L' U2 L F R F' D2"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Both of AG's attempts, with their own move sequences.
    expect(find.text("R U R' U'"), findsOneWidget);
    expect(find.text("L' U2 L F R F' D2"), findsWidgets);
    expect(find.text('Executed GA'), findsWidgets);
  });

  testWidgets('tapping a solved row shows its moves; raw readings say so',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _movesTimes(),
        cubeDriven: true,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 12000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();

    // A reconstructed solve: moves in the dialog, no raw disclaimer.
    await tester.tap(find.text('BA'));
    await tester.pumpAndSettle();
    expect(find.text("M U M' U'"), findsOneWidget);
    expect(find.textContaining('Raw reading'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // A declined parse: the raw reading, marked as such.
    await tester.tap(find.text('XT'));
    await tester.pumpAndSettle();
    expect(find.text("R L' U R' L U'"), findsOneWidget);
    expect(find.textContaining('Raw reading'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // A press-timed solve carries no moves: tapping opens nothing.
    await tester.tap(find.text('AG'));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a raw mistake reading is marked in the attempts dialog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _sampleTimes(),
        mistakes: const [
          AlgMistake(1, Alg("AG"), AlgMistakeKind.wrongCase,
              executed: "GA",
              moves: "R L' U R' L U'",
              movesReconstructed: false),
        ],
        cubeDriven: true,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 12000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text("R L' U R' L U'"), 120);
    await tester.tap(find.text("R L' U R' L U'"));
    await tester.pumpAndSettle();
    expect(find.textContaining('Raw reading'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cube run without mistakes: the count stays, showing zero',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800)); // phone width
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _sampleTimes(),
        cubeDriven: true,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 12000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The tile doesn't change shape run to run: the count shows, at zero.
    expect(find.text('SOLVED'), findsOneWidget);
    expect(find.text('6 (0)'), findsOneWidget);
    // But no errors section: there is nothing to list.
    expect(find.text('ERRORS (0)'), findsNothing);
  });

  testWidgets('three tiles on a phone: the values stay on one line',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: _sampleTimes(),
        mistakes: _sampleMistakes(),
        cubeDriven: true,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 12000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // A wrapping label used to push its value a line below the others'.
    double valueTop(String value) => tester
        .getTopLeft(find.descendant(
            of: find.byType(IntrinsicHeight), matching: find.text(value)))
        .dy;
    final solved = valueTop('6 (3)');
    expect(valueTop('5/6'), solved); // hit target — the label that wrapped
    expect(valueTop('0.82'), solved); // average
  });

  // The reported case, end to end: one 2.76s solve against a 3s target used to
  // draw an almost-empty bar, reading as if it were miles under target.
  testWidgets('sets: a lone near-target solve fills up to just short of the tick',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: [const AlgTime(1, 2760, Alg("BA"), timestamp: 1)],
        algType: AlgType.Corner,
        targetTime: 3.0,
        practiceType: PracticeType.sets,
        totalTimeMs: 2760,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // One row → the bar's fill box, then its target tick.
    final boxes = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .toList();
    expect(boxes, hasLength(2));
    expect(boxes[1].widthFactor, 0.65); // the tick, for reference
    expect(boxes[0].widthFactor, closeTo(0.598, 0.001)); // was 0.05
  });

  testWidgets('no cube: the solved tile drops the error count', (tester) async {
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
    // Only a cube detects errors, so a press-timed run shows a bare count —
    // not even a "(0)".
    expect(
        find.descendant(
            of: find.byType(IntrinsicHeight), matching: find.text('6')),
        findsOneWidget);
    expect(find.text('6 (0)'), findsNothing);
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

  testWidgets('sets: the edited target is handed back to the session',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    double? reported;
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: [const AlgTime(1, 800, Alg('BA'), timestamp: 1)],
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 800,
        onTargetTimeChanged: (t) => reported = t,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '1.20');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The timer keeps this for the rest of the session, so a later summary of
    // the same run doesn't revert to the value it was started with.
    expect(reported, 1.2);
  });

  // The last case of a run reaches the summary before its move reconstruction
  // finishes, so the summary has to take the row when it lands.
  testWidgets('a reconstruction landing after the summary opens is picked up',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final times = [
      const AlgTime(1, 770, Alg("BA"),
          timestamp: 1, recognitionMs: 300, moves: "M U M' U'"),
      const AlgTime(2, 900, Alg("VU"), timestamp: 2, recognitionMs: 400),
    ];
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);

    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: times,
        revision: revision,
        cubeDriven: true,
        algType: AlgType.Corner,
        targetTime: 0.85,
        practiceType: PracticeType.sets,
        totalTimeMs: 12000,
      ),
      AppPalette.slate,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // VU is built with no moves, so its row is inert. Don't tap it here: a tap
    // rebuilds the row on its own and would mask the notifier doing the work.

    // What the timer does when the replay lands: swap the row in place, bump.
    final i = times.indexWhere((t) => t.alg.name == "VU");
    times[i] = AlgTime(times[i].index, times[i].timeMs, times[i].alg,
        timestamp: times[i].timestamp,
        recognitionMs: times[i].recognitionMs,
        moves: "R U R' U'");
    revision.value++;
    await tester.pumpAndSettle();

    // The same row now opens its moves without the summary being reopened.
    await tester.tap(find.text('VU'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text("R U R' U'"), findsOneWidget);
  });
}
