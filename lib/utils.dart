String timeToString(int timeMs) {
  double floatValue = timeMs / 1000;
  return floatValue.toStringAsFixed(1);
}
