import 'package:flutter/material.dart';

const Color textColor = Colors.white;
const Color titleColor = Colors.grey;

ThemeData mainTheme = ThemeData(
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Color(0xff6750a4),
    brightness: Brightness.light,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.black54,
    foregroundColor: Colors.white,
    titleTextStyle: TextStyle(
      fontSize: 38,
      color: Colors.white,
    ),
  ),
  textTheme: TextTheme(
    displayLarge: const TextStyle(
      fontSize: 72,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    displayMedium: const TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    displaySmall: const TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    labelLarge: const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    labelMedium: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    labelSmall: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    titleLarge: const TextStyle(
      fontSize: 48,
      // fontStyle: FontStyle.italic,
      fontWeight: FontWeight.normal,
      color: titleColor,
    ),
    titleMedium: const TextStyle(
      fontSize: 32,
      // fontStyle: FontStyle.italic,
      fontWeight: FontWeight.normal,
      color: titleColor,
    ),
    titleSmall: const TextStyle(
      fontSize: 24,
      // fontStyle: FontStyle.italic,
      fontWeight: FontWeight.normal,
      color: titleColor,
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
      // backgroundColor: COLOR_ACCENT,
      ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ButtonStyle(
      padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
      // backgroundColor: WidgetStateProperty.all<Color>(COLOR_ACCENT)
    ),
  ),
);
