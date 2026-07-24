import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/l10n/app_localizations.dart';
import 'package:three_style_trainer/screens/letter_pairs_list_screen.dart';
import 'package:three_style_trainer/theme/app_palette.dart';
import 'package:three_style_trainer/theme/theme_scope.dart';

// Without a connected cube the screen is the plain static list (its long-
// standing behaviour); the cube-driven ordered drill layers on top only when a
// cube is present. This covers the static path and the algType constructor arg.
Widget _host(Widget child) => ThemeScope(
      palette: AppPalette.slate,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(AppPalette.slate),
        home: child,
      ),
    );

void main() {
  testWidgets('renders the set as a grid of letter pairs (no cube)',
      (tester) async {
    final provider = CornersAlgProvider(setIndices: const [0]);
    // The pairs the screen will list (getNextAlg drains, so snapshot first).
    final expected = <String>[];
    Alg? a;
    while ((a = provider.getNextAlg()) != null) {
      expected.add(a!.name);
    }
    provider.reset();
    expect(expected, isNotEmpty);

    await tester.pumpWidget(
        _host(LetterPairsListScreen(provider, AlgType.Corner)));
    await tester.pumpAndSettle();

    // No cube: no status bar, and every (visible) pair is drawn. The set is
    // small enough to fit without scrolling.
    expect(find.text(AppLocalizations.of(tester.element(
                find.byType(LetterPairsListScreen)))!
            .letterPairsNextPrompt(expected.first)),
        findsNothing);
    for (final pair in expected) {
      expect(find.text(pair, findRichText: true), findsOneWidget,
          reason: 'pair $pair should be listed');
    }
  });
}
