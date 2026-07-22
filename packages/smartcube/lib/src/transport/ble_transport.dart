/// A thin BLE abstraction the drivers program against, so protocol code never
/// imports `flutter_blue_plus` directly and stays unit-testable with a fake.
/// The concrete implementation is [FlutterBluePlusTransport].
abstract class BleTransport {
  /// Start scanning; emits every advertisement seen. Caller filters by brand.
  Stream<BleScanResult> scan();

  Future<void> stopScan();

  /// Connect to a peripheral by its platform id and discover its GATT table.
  Future<BlePeripheral> connect(String deviceId);
}

/// One advertisement packet from a scan.
class BleScanResult {
  /// Platform device id. On Android this is the MAC; on Windows/iOS it is an
  /// opaque handle (the MAC must then come from name/advertisement).
  final String deviceId;
  final String name;
  final List<String> serviceUuids;

  /// Manufacturer-specific data keyed by company identifier code.
  final Map<int, List<int>> manufacturerData;

  const BleScanResult({
    required this.deviceId,
    required this.name,
    this.serviceUuids = const [],
    this.manufacturerData = const {},
  });
}

/// A connected peripheral.
abstract class BlePeripheral {
  String get id;
  String get name;

  /// `true` while connected; emits `false` when the link drops.
  Stream<bool> get connected;

  Future<List<BleService>> discoverServices();

  Future<void> disconnect();
}

abstract class BleService {
  String get uuid;
  List<BleCharacteristic> get characteristics;
}

abstract class BleCharacteristic {
  String get uuid;

  /// Notification/indication values pushed by the peripheral.
  Stream<List<int>> get onValue;

  /// Subscribe to notifications on this characteristic.
  Future<void> enableNotifications();

  /// Read the characteristic's current value (a GATT read, not a notification).
  Future<List<int>> read();

  Future<void> write(List<int> data, {bool withoutResponse = false});
}

/// Normalise a BLE UUID to a lowercase 128-bit string for comparison. Accepts
/// 16-bit short form (`"cb1"` / `"0783"`) and expands it into the Bluetooth base
/// UUID.
String normalizeUuid(String uuid) {
  var u = uuid.toLowerCase().replaceAll('{', '').replaceAll('}', '');
  if (RegExp(r'^[0-9a-f]{4}$').hasMatch(u)) {
    u = '0000$u-0000-1000-8000-00805f9b34fb';
  }
  return u;
}
