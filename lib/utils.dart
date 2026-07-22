import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'smart_cube/cube_orientation.dart';

/// An alg name as a span with the audio-scheme vowel colouring: é/É render
/// green and è/È orange (closed/open vowel sounds — a visual aid only).
TextSpan algTextSpan(String text, TextStyle style) {
  const greenCharacters = {'é', 'É'};
  const orangeCharacters = {'è', 'È'};
  return TextSpan(
    children: [
      for (final c in text.characters)
        TextSpan(
          text: c,
          style: greenCharacters.contains(c)
              ? style.copyWith(color: Colors.green)
              : orangeCharacters.contains(c)
                  ? style.copyWith(color: Colors.orange)
                  : style,
        ),
    ],
  );
}

String timeToString(int timeMs, {int fractionDigits = 1}) {
  double floatValue = timeMs / 1000;
  return floatValue.toStringAsFixed(fractionDigits);
}

String cubeColourName(AppLocalizations l10n, CubeColour c) {
  switch (c) {
    case CubeColour.white:
      return l10n.colourWhite;
    case CubeColour.yellow:
      return l10n.colourYellow;
    case CubeColour.green:
      return l10n.colourGreen;
    case CubeColour.blue:
      return l10n.colourBlue;
    case CubeColour.red:
      return l10n.colourRed;
    case CubeColour.orange:
      return l10n.colourOrange;
  }
}

/// Formats a (potentially long) elapsed duration as `m:ss`, e.g. "2:03".
String totalTimeToString(int timeMs) {
  int totalSeconds = (timeMs / 1000).round();
  int minutes = totalSeconds ~/ 60;
  int seconds = totalSeconds % 60;
  return "$minutes:${seconds.toString().padLeft(2, '0')}";
}

bool isUnderTargetTime(int timeMs, double targetTime) {
  return timeMs / 1000 <= targetTime;
}
