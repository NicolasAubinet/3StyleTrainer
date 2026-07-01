import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_palette.dart';

/// Holds the selected [AppThemeId] and persists it. The root widget listens to
/// [notifier] and rebuilds the app when the theme changes.
class ThemeController {
  static const String _prefsKey = "app_theme";

  static final ThemeController _singleton = ThemeController._internal();
  factory ThemeController() => _singleton;
  ThemeController._internal();

  final ValueNotifier<AppThemeId> notifier = ValueNotifier(AppThemeId.slate);

  AppThemeId get current => notifier.value;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefsKey);
    if (name != null) {
      notifier.value = AppThemeId.values.firstWhere(
        (e) => e.name == name,
        orElse: () => AppThemeId.slate,
      );
    }
  }

  Future<void> set(AppThemeId id) async {
    notifier.value = id;
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_prefsKey, id.name);
  }
}
