import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:three_style_trainer/settings.dart';

import 'l10n/app_localizations.dart';
import 'screens/menu_screen.dart';
import 'theme/app_palette.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_scope.dart';

void main() {
  Settings().initPrefs();
  DatabaseManager().initDatabase(
    onReady: () => ThemeController().load().then((_) => runApp(MainApp())),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeId>(
      valueListenable: ThemeController().notifier,
      builder: (context, themeId, _) {
        final palette = themeId.palette;
        return ThemeScope(
          palette: palette,
          child: MaterialApp(
            title: '3-Style Trainer',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(palette),
            home: MenuScreen(),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [
              Locale('en'), // English
            ],
          ),
        );
      },
    );
  }
}
