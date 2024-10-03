import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:three_style_trainer/settings.dart';

import 'screens/menu_screen.dart';
import 'themes.dart';

void main() {
  Settings().initPrefs();
  DatabaseManager().initDatabase(onReady: () => runApp(MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3-Style Trainer',
      theme: mainTheme,
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
    );
  }
}
