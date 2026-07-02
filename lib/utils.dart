String timeToString(int timeMs, {int fractionDigits = 1}) {
  double floatValue = timeMs / 1000;
  return floatValue.toStringAsFixed(fractionDigits);
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
