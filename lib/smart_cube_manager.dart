import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smartcube/smartcube.dart';

/// App-wide holder for the current smart-cube connection. A singleton (like
/// [Settings] / [DatabaseManager]) so the connection survives navigation and any
/// screen can observe it. Everything smart-cube-related in the app funnels through here.
class SmartCubeManager {
  static final SmartCubeManager _instance = SmartCubeManager._();
  factory SmartCubeManager() => _instance;
  SmartCubeManager._();

  final CubeScanner _scanner = createCubeScanner();

  SmartCube? _cube;
  SmartCube? get cube => _cube;
  bool get isConnected => _cube != null;

  final ValueNotifier<CubeConnection> connection =
      ValueNotifier(CubeConnection.disconnected);
  final ValueNotifier<int?> battery = ValueNotifier(null);
  final ValueNotifier<String?> cubeName = ValueNotifier(null);

  StreamSubscription<CubeConnection>? _connSub;
  Timer? _batteryTimer;

  Stream<DiscoveredCube> scan() => _scanner.scan();
  Future<void> stopScan() => _scanner.stopScan();

  Future<void> connect(DiscoveredCube device, {String? macAddress}) async {
    connection.value = CubeConnection.connecting;
    cubeName.value = device.name;
    final cube = await _scanner.connect(device, macAddress: macAddress);
    _cube = cube;
    connection.value = cube.connection;
    _connSub = cube.connectionEvents.listen((c) {
      connection.value = c;
      if (c == CubeConnection.lost || c == CubeConnection.disconnected) {
        _cleanup();
      }
    });
    await _refreshBattery();
    _batteryTimer = Timer.periodic(
        const Duration(seconds: 60), (_) => _refreshBattery());
  }

  Future<void> _refreshBattery() async {
    final b = await _cube?.batteryLevel();
    if (b != null) battery.value = b;
  }

  Future<void> disconnect() async {
    final cube = _cube;
    _cleanup();
    await cube?.disconnect();
  }

  void _cleanup() {
    _batteryTimer?.cancel();
    _batteryTimer = null;
    _connSub?.cancel();
    _connSub = null;
    _cube = null;
    connection.value = CubeConnection.disconnected;
    battery.value = null;
    cubeName.value = null;
  }
}
