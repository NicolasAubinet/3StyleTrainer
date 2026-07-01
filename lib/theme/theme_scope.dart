import 'package:flutter/widgets.dart';

import 'app_palette.dart';

/// Exposes the active [AppPalette] to the widget tree. Read it with
/// `context.palette`.
class ThemeScope extends InheritedWidget {
  final AppPalette palette;

  const ThemeScope({
    super.key,
    required this.palette,
    required super.child,
  });

  static AppPalette of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, "No ThemeScope found in context");
    return scope!.palette;
  }

  @override
  bool updateShouldNotify(ThemeScope oldWidget) => palette.id != oldWidget.palette.id;
}

extension PaletteAccess on BuildContext {
  AppPalette get palette => ThemeScope.of(this);
}
