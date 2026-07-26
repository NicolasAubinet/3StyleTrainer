/// The link came up but nothing the cube said could be decoded. Brands that
/// derive their cipher key from the cube's MAC cannot tell a wrong MAC from a
/// silent cube, so the driver probes for one decodable message and throws this
/// when none arrives: the MAC was wrong. Callers should ask the user for the
/// real one and reconnect with it.
class CubeMacRejectedException implements Exception {
  /// The MAC that failed, so the caller can show what was tried.
  final String attemptedMac;

  const CubeMacRejectedException(this.attemptedMac);

  @override
  String toString() =>
      'The cube sent nothing readable using MAC $attemptedMac (wrong MAC?)';
}
