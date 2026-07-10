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

void main() {
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
