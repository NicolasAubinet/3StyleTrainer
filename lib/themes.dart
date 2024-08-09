import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    titleTextStyle: GoogleFonts.firaCode(
      fontSize: 32,
      color: Colors.white,
    ),
  ),
  textTheme: TextTheme(
    displayLarge: GoogleFonts.firaCode(
      fontSize: 72,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    displayMedium: GoogleFonts.firaCode(
      fontSize: 44,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    displaySmall: GoogleFonts.firaCode(
      fontSize: 32,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    labelLarge: GoogleFonts.firaCode(
      fontSize: 24,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    labelMedium: GoogleFonts.firaCode(
      fontSize: 18,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    labelSmall: GoogleFonts.firaCode(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: textColor,
    ),
    titleLarge: GoogleFonts.firaCode(
      fontSize: 48,
      // fontStyle: FontStyle.italic,
      fontWeight: FontWeight.normal,
      color: titleColor,
    ),
    titleMedium: GoogleFonts.firaCode(
      fontSize: 32,
      // fontStyle: FontStyle.italic,
      fontWeight: FontWeight.normal,
      color: titleColor,
    ),
    titleSmall: GoogleFonts.firaCode(
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
