import 'model/connection.dart';
import 'model/cube_error.dart';
import 'smart_cube.dart';
import 'transport/ble_transport.dart';

/// How often a driver re-asks for the cube's state while its model is
/// un-anchored. Nothing is emitted meanwhile, so this is the stall the user feels.
const Duration anchorRetryInterval = Duration(milliseconds: 250);

/// How long a driver keeps asking for a decodable message during the handshake
/// before it blames the MAC and throws [CubeMacRejectedException]. Generous: a
/// slow link must not be mistaken for a wrong key.
const Duration defaultMacProbeTimeout = Duration(seconds: 4);

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

  /// GATT services this driver opens once connected. Usually the same as
  /// [serviceUuids], but a driver may match on a name yet still need services
  /// it never advertises. Web Bluetooth refuses access to any service not
  /// declared up front, so these are what get passed as `optionalServices`.
  List<String> get gattServiceUuids => serviceUuids;

  bool matches(CubeAdvertisement adv) {
    final name = adv.name;
    if (name != null && namePrefixes.any(name.startsWith)) return true;
    final claimed = serviceUuids.map(normalizeUuid).toSet();
    return adv.serviceUuids.any((u) => claimed.contains(normalizeUuid(u)));
  }

  /// `true` when this cube needs a MAC the caller must supply because it can't
  /// be derived from the advertisement (name / manufacturer data).
  bool needsExplicitMac(CubeAdvertisement adv) => false;

  /// Human-readable model label when the driver can tell more precisely than
  /// [brand]. Null → callers fall back to the brand name.
  String? modelName(CubeAdvertisement adv) => null;

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

  /// Every GATT service any registered driver may open, normalised.
  Set<String> get gattServiceUuids =>
      _drivers.expand((d) => d.gattServiceUuids).map(normalizeUuid).toSet();

  CubeDriver? driverFor(CubeAdvertisement adv) {
    for (final d in _drivers) {
      if (d.matches(adv)) return d;
    }
    return null;
  }
}
