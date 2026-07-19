import 'model/connection.dart';
import 'reconstruct/move_prior.dart';
import 'smart_cube.dart';
import 'transport/ble_transport.dart';

/// Advertisement data a driver inspects to decide whether it handles a device.
class CubeAdvertisement {
  final String id;
  final String? name;
  final List<String> serviceUuids;

  /// Manufacturer data keyed by company identifier code (CIC). Used for MAC
  /// extraction on platforms that expose it.
  final Map<int, List<int>> manufacturerData;

  const CubeAdvertisement({
    required this.id,
    this.name,
    this.serviceUuids = const [],
    this.manufacturerData = const {},
  });
}

/// One brand's protocol implementation. Kept PURE — no Flutter/BLE imports — so
/// it unit-tests from captured byte fixtures and ports cleanly to other
/// languages (e.g. a future Kotlin build for the Nano Timer).
abstract class CubeDriver {
  CubeBrand get brand;

  /// Name prefixes this driver claims (e.g. `WCU_MY3` for the MoYu V10).
  List<String> get namePrefixes;

  /// Service UUIDs this driver claims, for name-less devices.
  List<String> get serviceUuids;

  /// How much this cube's per-move timestamps can be trusted.
  ///
  /// Slice reconstruction groups turns into physical motions by timing, so a
  /// cube without a real per-move clock cannot support it. Declared per driver
  /// because the reconstruction's own confidence cannot detect bad timing — it
  /// stays high while the answer degrades.
  TimingQuality get timingQuality => TimingQuality.perMoveClock;

  bool matches(CubeAdvertisement adv) {
    final name = adv.name;
    if (name != null && namePrefixes.any(name.startsWith)) return true;
    final claimed = serviceUuids.map(normalizeUuid).toSet();
    return adv.serviceUuids.any((u) => claimed.contains(normalizeUuid(u)));
  }

  /// `true` when this cube needs a MAC the caller must supply because it can't
  /// be derived from the advertisement (name / manufacturer data).
  bool needsExplicitMac(CubeAdvertisement adv) => false;

  /// Bring up a connected [SmartCube] over an already-open [peripheral].
  Future<SmartCube> connect(
    BlePeripheral peripheral,
    CubeAdvertisement adv, {
    String? macAddress,
  });
}

/// Global registry of brand drivers. Each driver registers itself; the scanner
/// asks the registry which driver handles a discovered advertisement.
class CubeDriverRegistry {
  CubeDriverRegistry._();
  static final CubeDriverRegistry instance = CubeDriverRegistry._();

  final List<CubeDriver> _drivers = [];

  void register(CubeDriver driver) => _drivers.add(driver);

  Iterable<CubeDriver> get drivers => List.unmodifiable(_drivers);

  CubeDriver? driverFor(CubeAdvertisement adv) {
    for (final d in _drivers) {
      if (d.matches(adv)) return d;
    }
    return null;
  }
}
