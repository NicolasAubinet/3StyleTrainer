import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/l10n/app_localizations.dart';
import 'package:three_style_trainer/practice_type.dart';
import 'package:three_style_trainer/screens/session_summary_screen.dart';
import 'package:three_style_trainer/theme/app_palette.dart';
import 'package:three_style_trainer/theme/theme_scope.dart';

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
      const AlgTime(1, 770, Alg("BA")),
      const AlgTime(2, 790, Alg("XT")),
      const AlgTime(3, 800, Alg("AG")),
      const AlgTime(4, 810, Alg("UF-DR")), // long 2-flip name
      const AlgTime(5, 820, Alg("BL")),
      const AlgTime(6, 910, Alg("VU")),
    ];

void main() {
  for (final palette in [AppPalette.slate, AppPalette.cubeFace]) {
    testWidgets('renders time-race summary (${palette.id.name})',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640)); // narrow
      await tester.pumpWidget(_host(
        SessionSummaryScreen(
          algTimes: _sampleTimes(),
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
      const AlgTime(1, 800, Alg('AA')),
      const AlgTime(2, 900, Alg('BB')),
      const AlgTime(3, 500, Alg('CC')),
    ];
    await tester.pumpWidget(_host(
      SessionSummaryScreen(
        algTimes: times,
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
}
