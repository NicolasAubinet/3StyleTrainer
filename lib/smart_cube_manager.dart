import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smartcube/smartcube.dart';

/// App-wide holder for the current smart-cube connection. A singleton (like
/// [Settings] / [DatabaseManager]) so the connection survives navigation and any
/// screen can observe it. Everything smart-cube-related in the app funnels through here.
///
/// The cube's streams are re-published here rather than exposed directly: a
/// reconnect builds a *new* [SmartCube], and listeners must not have to
/// resubscribe (or notice) when that happens.
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

  final _moveCtrl = StreamController<CubeMove>.broadcast();
  final _stateCtrl = StreamController<CubeState>.broadcast();
  final _resyncCtrl = StreamController<CubeState>.broadcast();

  Stream<CubeMove> get moves => _moveCtrl.stream;
  Stream<CubeState> get states => _stateCtrl.stream;

  /// Tracking was re-anchored on the cube's own state (after lost moves or a
  /// reconnect) — any baseline taken before this is stale.
  Stream<CubeState> get resyncs => _resyncCtrl.stream;

  final List<StreamSubscription> _cubeSubs = [];
  Timer? _batteryTimer;
  Timer? _reconnectTimer;

  // What to reconnect to, kept for as long as the user wants a cube.
  DiscoveredCube? _device;
  String? _macAddress;

  Stream<DiscoveredCube> scan() => _scanner.scan();
  Future<void> stopScan() => _scanner.stopScan();

  Future<void> connect(DiscoveredCube device, {String? macAddress}) async {
    _device = device;
    _macAddress = macAddress;
    connection.value = CubeConnection.connecting;
    cubeName.value = device.name;
    await _openCube();
  }

  Future<void> _openCube() async {
    final device = _device;
    if (device == null) return;
    final cube = await _scanner.connect(device, macAddress: _macAddress);
    _cube = cube;
    _bind(cube);
    connection.value = cube.connection;
    await _refreshBattery();
    _batteryTimer?.cancel();
    _batteryTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _refreshBattery());
  }

  void _bind(SmartCube cube) {
    for (final s in _cubeSubs) {
      s.cancel();
    }
    _cubeSubs
      ..clear()
      ..add(cube.moves.listen(_moveCtrl.add))
      ..add(cube.states.listen(_stateCtrl.add))
      ..add(cube.resyncs.listen(_resyncCtrl.add))
      ..add(cube.connectionEvents.listen((c) {
        if (c == CubeConnection.lost) {
          _startReconnecting();
        } else if (c == CubeConnection.disconnected) {
          _cleanup();
        } else {
          connection.value = c;
        }
      }));
  }

  // A dropped link usually means the cube went to sleep, and it comes back the
  // moment a face is turned. Keep retrying until it does (or the user gives up
  // and disconnects) rather than dropping the session.
  void _startReconnecting() {
    if (_reconnectTimer != null) return;
    if (_device == null) {
      _cleanup();
      return;
    }
    _cube = null;
    battery.value = null;
    connection.value = CubeConnection.reconnecting;
    _reconnectTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _tryReconnect());
    _tryReconnect();
  }

  Future<void> _tryReconnect() async {
    if (_cube != null || _device == null) return;
    try {
      await _openCube();
    } catch (_) {
      return; // asleep or out of range — the timer tries again
    }
    final cube = _cube;
    if (cube != null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      // Pull the real state before announcing the resync: the cube was turned
      // while it was away (that is usually what woke it), so any baseline taken
      // before the drop is stale.
      _resyncCtrl.add(await cube.requestState());
    }
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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    for (final s in _cubeSubs) {
      s.cancel();
    }
    _cubeSubs.clear();
    _cube = null;
    _device = null;
    _macAddress = null;
    connection.value = CubeConnection.disconnected;
    battery.value = null;
    cubeName.value = null;
  }
}
