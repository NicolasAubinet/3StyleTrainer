import 'package:flutter/material.dart';

const Color textColor = Colors.white;
const Color titleColor = Colors.white70;

const String FONT = "firaCode";

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
      fontFamily: FONT,
      fontSize: 32,
      color: Colors.white,
    ),
  ),
  textTheme: TextTheme(
    displayLarge: TextStyle(
      fontFamily: FONT,
      fontSize: 72,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    displayMedium: TextStyle(
      fontFamily: FONT,
      fontSize: 44,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    displaySmall: TextStyle(
      fontFamily: FONT,
      fontSize: 32,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    labelLarge: TextStyle(
      fontFamily: FONT,
      fontSize: 24,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    labelMedium: TextStyle(
      fontFamily: FONT,
      fontSize: 18,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    labelSmall: TextStyle(
      fontFamily: FONT,
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    titleLarge: TextStyle(
      fontFamily: FONT,
      fontSize: 48,
      // fontStyle: FontStyle.italic,
      fontWeight: FontWeight.normal,
      color: titleColor,
    ),
    titleMedium: TextStyle(
      fontFamily: FONT,
      fontSize: 32,
      // fontStyle: FontStyle.italic,
      fontWeight: FontWeight.normal,
      color: titleColor,
    ),
    titleSmall: TextStyle(
      fontFamily: FONT,
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
