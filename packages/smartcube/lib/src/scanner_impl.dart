import 'driver.dart';
import 'drivers/gan_driver.dart';
import 'drivers/moyu_v10_driver.dart';
import 'model/connection.dart';
import 'scanner.dart';
import 'smart_cube.dart';
import 'transport/ble_transport.dart';
import 'transport/flutter_blue_plus_transport.dart';

/// Default [CubeScanner]: runs a BLE scan through a [BleTransport], matches each
/// advertisement against the driver registry, and connects via the winning
/// driver. Brand detection is automatic.
class DefaultCubeScanner implements CubeScanner {
  final BleTransport _transport;
  final Map<String, CubeAdvertisement> _adv = {};
  final Map<String, CubeDriver> _drivers = {};

  DefaultCubeScanner(this._transport);

  @override
  Stream<DiscoveredCube> scan() {
    return _transport.scan().expand((r) {
      final adv = CubeAdvertisement(
        id: r.deviceId,
        name: r.name,
        serviceUuids: r.serviceUuids,
        manufacturerData: r.manufacturerData,
      );
      final driver = CubeDriverRegistry.instance.driverFor(adv);
      if (driver == null) return const <DiscoveredCube>[];
      _adv[r.deviceId] = adv;
      _drivers[r.deviceId] = driver;
      return [
        DiscoveredCube(
          id: r.deviceId,
          name: r.name,
          brand: driver.brand,
          needsMac: driver.needsExplicitMac(adv),
        ),
      ];
    });
  }

  @override
  Future<SmartCube> connect(DiscoveredCube cube, {String? macAddress}) async {
    final driver = _drivers[cube.id];
    final adv = _adv[cube.id];
    if (driver == null || adv == null) {
      throw StateError('Scan and discover ${cube.id} before connecting');
    }
    final peripheral = await _transport.connect(cube.id);
    return driver.connect(peripheral, adv, macAddress: macAddress);
  }

  @override
  Future<void> stopScan() => _transport.stopScan();
}

var _driversRegistered = false;

void _registerBuiltInDrivers() {
  if (_driversRegistered) return;
  _driversRegistered = true;
  CubeDriverRegistry.instance.register(MoyuV10Driver());
  CubeDriverRegistry.instance.register(GanDriver());
}

/// Create a scanner wired to the built-in drivers. Pass a custom [transport] to
/// override the default `flutter_blue_plus` backend (e.g. for tests).
CubeScanner createCubeScanner({BleTransport? transport}) {
  _registerBuiltInDrivers();
  return DefaultCubeScanner(transport ?? FlutterBluePlusTransport());
}
