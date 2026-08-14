import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_transport.dart';

/// [BleTransport] backed by `flutter_blue_plus` (Android / Windows / macOS /
/// Linux / iOS; web via its companion). The only file in the package that
/// imports the plugin.
class FlutterBluePlusTransport implements BleTransport {
  /// Devices seen during the current scan, so [connect] reuses the real
  /// [BluetoothDevice] object instead of reconstructing it.
  final Map<String, BluetoothDevice> _seen = {};

  /// Services to declare as `optionalServices` on web. Web Bluetooth blocks
  /// access to any service not named in `requestDevice`, so an undeclared one
  /// fails at discovery with a `SecurityError`. Ignored on other platforms.
  final List<Guid> _webOptionalServices;

  FlutterBluePlusTransport({List<String> webOptionalServices = const []})
      : _webOptionalServices = webOptionalServices.map(Guid.new).toList();

  @override
  Stream<BleScanResult> scan() async* {
    await FlutterBluePlus.startScan(webOptionalServices: _webOptionalServices);
    yield* FlutterBluePlus.onScanResults.expand((batch) => batch).map(_toResult);
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<BlePeripheral> connect(String deviceId) async {
    final device = _seen[deviceId];
    if (device == null) {
      throw StateError('Unknown device $deviceId — scan before connecting');
    }
    // flutter_blue_plus 2.x requires declaring a license. nonprofit covers
    // personal / open-source / nonprofit use; switch to License.commercial (a
    // paid FBP license) if this app is ever distributed commercially — or pin
    // flutter_blue_plus to 1.x (BSD, no license arg) to avoid the question.
    await device.connect(license: License.nonprofit);
    return _FbpPeripheral(device);
  }

  BleScanResult _toResult(ScanResult r) {
    _seen[r.device.remoteId.str] = r.device;
    final adv = r.advertisementData;
    return BleScanResult(
      deviceId: r.device.remoteId.str,
      name: adv.advName.isNotEmpty ? adv.advName : r.device.platformName,
      serviceUuids: adv.serviceUuids.map((g) => normalizeUuid(g.toString())).toList(),
      manufacturerData: adv.manufacturerData,
    );
  }
}

class _FbpPeripheral implements BlePeripheral {
  final BluetoothDevice _device;
  _FbpPeripheral(this._device);

  @override
  String get id => _device.remoteId.str;

  @override
  String get name => _device.platformName;

  @override
  Stream<bool> get connected =>
      _device.connectionState.map((s) => s == BluetoothConnectionState.connected);

  @override
  Future<List<BleService>> discoverServices() async {
    final services = await _device.discoverServices();
    return services.map((s) => _FbpService(s)).toList();
  }

  @override
  Future<void> disconnect() => _device.disconnect();
}

class _FbpService implements BleService {
  final BluetoothService _service;
  _FbpService(this._service);

  @override
  String get uuid => normalizeUuid(_service.uuid.toString());

  @override
  List<BleCharacteristic> get characteristics =>
      _service.characteristics.map((c) => _FbpCharacteristic(c)).toList();
}

class _FbpCharacteristic implements BleCharacteristic {
  final BluetoothCharacteristic _chr;
  _FbpCharacteristic(this._chr);

  @override
  String get uuid => normalizeUuid(_chr.uuid.toString());

  @override
  Stream<List<int>> get onValue => _chr.onValueReceived;

  @override
  Future<void> enableNotifications() => _chr.setNotifyValue(true);

  @override
  Future<List<int>> read() => _chr.read();

  /// Writes with whichever write type the characteristic actually declares:
  /// QiYi's single fff6 characteristic is write-without-response only, and
  /// asking for the unsupported type throws before a byte leaves the phone.
  @override
  Future<void> write(List<int> data, {bool withoutResponse = false}) {
    final props = _chr.properties;
    final noResponse = withoutResponse
        ? props.writeWithoutResponse || !props.write
        : !props.write && props.writeWithoutResponse;
    return _chr.write(data, withoutResponse: noResponse);
  }
}
