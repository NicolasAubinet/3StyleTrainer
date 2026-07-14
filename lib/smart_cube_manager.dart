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
  /// reconnect) — any baseline taken before this is stale. Every reconnect ends
  /// in one, so listeners may ignore the cube from the drop until this fires.
  Stream<CubeState> get resyncs => _resyncCtrl.stream;

  final List<StreamSubscription> _cubeSubs = [];
  Timer? _batteryTimer;
  Timer? _reconnectTimer;
  // Without these a slow attempt outlives the retry tick and we dial twice.
  bool _retrying = false;
  bool _opening = false;

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
    if (device == null || _opening) return;
    _opening = true;
    try {
      final cube = await _scanner.connect(device, macAddress: _macAddress);
      // Disconnected (or switched cubes) while we dialled: this link is nobody's.
      if (!identical(_device, device)) {
        await cube.disconnect();
        return;
      }
      _cube = cube;
      _bind(cube);
      connection.value = cube.connection;
    } finally {
      _opening = false;
    }
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
  Future<void> _startReconnecting() async {
    if (_retrying) return;
    if (_device == null) {
      _cleanup();
      return;
    }
    _retrying = true;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    battery.value = null;
    connection.value = CubeConnection.reconnecting;
    // Hang up before dialling again: a leaked link keeps its notify subscription
    // and pull timer alive, and the new connection ends up fighting it.
    await _releaseCube();
    if (!_retrying) return; // disconnected while we were letting go
    _reconnectTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _tryReconnect());
    _tryReconnect();
  }

  Future<void> _tryReconnect() async {
    if (_cube != null || _device == null || _opening) return;
    try {
      await _openCube();
    } catch (_) {
      // Asleep, out of range, or a failed handshake: drop whatever link that
      // left behind so the next try starts clean.
      await _releaseCube();
      return;
    }
    final cube = _cube;
    if (cube == null) return;
    _retrying = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // Pull the real state before announcing the resync: the cube was turned while
    // it was away (that is usually what woke it). Listeners wait for the resync,
    // so it must go out even if the pull fails — the tracked state will do.
    CubeState state;
    try {
      state = await cube.requestState();
    } catch (_) {
      state = cube.currentState;
    }
    if (identical(_cube, cube)) _resyncCtrl.add(state);
  }

  // Let go of the current cube. Stop listening first: its own disconnected event
  // must not reach [_bind]'s listener, which would end the session.
  Future<void> _releaseCube() async {
    final cube = _cube;
    _cube = null;
    for (final s in _cubeSubs) {
      s.cancel();
    }
    _cubeSubs.clear();
    try {
      await cube?.disconnect();
    } catch (_) {
      // Already gone — nothing left to close.
    }
  }

  Future<void> _refreshBattery() async {
    try {
      final b = await _cube?.batteryLevel();
      if (b != null) battery.value = b;
    } catch (_) {
      // A battery read failing is not worth dropping the session over.
    }
  }

  Future<void> disconnect() async {
    final cube = _cube;
    _cleanup();
    try {
      await cube?.disconnect();
    } catch (_) {
      // Already gone.
    }
  }

  void _cleanup() {
    _retrying = false;
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
