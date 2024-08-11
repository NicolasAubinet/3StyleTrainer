String timeToString(int timeMs, {int fractionDigits = 1}) {
  double floatValue = timeMs / 1000;
  return floatValue.toStringAsFixed(fractionDigits);
}

bool isUnderTargetTime(int timeMs, double targetTime) {
  return timeMs / 1000 <= targetTime;
}
