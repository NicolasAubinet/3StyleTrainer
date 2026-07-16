/// Lifecycle of a cube connection. [lost] is a link that dropped on its own (the
/// cube slept, or went out of range) and may come back; [disconnected] is final.
enum CubeConnection { disconnected, scanning, connecting, reconnecting, ready, lost }

/// Smart-cube brands the scanner can recognise. `unknown` is matched by service
/// UUID when the device name is uninformative.
enum CubeBrand { moyuV10, moyuAi, gan, qiyi, giiker, gocube, unknown }

/// A cube found during a scan, before connecting.
class DiscoveredCube {
  /// Platform BLE id (not the MAC — the MAC may still need deriving).
  final String id;
  final String name;
  final CubeBrand brand;

  /// `true` when this cube needs a MAC *and* it could not be obtained
  /// automatically (name-derivation / advertisement), so the caller must supply
  /// one. Note QiYi needs one too despite its fixed key — the MAC is what its
  /// hello handshake carries.
  final bool needsMac;

  const DiscoveredCube({
    required this.id,
    required this.name,
    required this.brand,
    this.needsMac = false,
  });

  @override
  String toString() => 'DiscoveredCube($name, ${brand.name})';
}
