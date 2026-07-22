import 'dart:async';

import '../driver.dart';
import '../model/connection.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';
import '../reconstruct/timing_quality.dart';
import '../smart_cube.dart';
import '../transport/ble_transport.dart';
import 'giiker_parser.dart';

/// Driver for Giiker i2/i3 and the Xiaomi Mi Smart Magic Cube (the same cube
/// under Xiaomi branding), ported from csTimer `giikercube.js` (GPL-3.0). No
/// MAC, no handshake: the cube pushes its full state on every turn; the initial
/// state comes from a plain GATT read of the same characteristic.
class GiikerDriver extends CubeDriver {
  static const String dataServiceUuid = '0000aadb-0000-1000-8000-00805f9b34fb';
  static const String dataChrUuid = '0000aadc-0000-1000-8000-00805f9b34fb';

  static const String rwServiceUuid = '0000aaaa-0000-1000-8000-00805f9b34fb';
  static const String rwReadChrUuid = '0000aaab-0000-1000-8000-00805f9b34fb';
  static const String rwWriteChrUuid = '0000aaac-0000-1000-8000-00805f9b34fb';

  /// Written to the RW service to request battery; the answer arrives as a
  /// notification whose byte 1 is the level.
  static const int reqBattery = 0xb5;

  @override
  CubeBrand get brand => CubeBrand.giiker;

  @override
  List<String> get namePrefixes => const ['Gi', 'Mi Smart Magic Cube', 'Hi-'];

  @override
  List<String> get serviceUuids => const [dataServiceUuid];

  @override
  String? modelName(CubeAdvertisement adv) {
    final name = adv.name;
    if (name == null) return null;
    if (name.startsWith('Mi Smart')) return 'Mi Smart Magic Cube';
    if (name.startsWith('Gi')) return 'Giiker';
    return null;
  }

  @override
  Future<SmartCube> connect(
    BlePeripheral peripheral,
    CubeAdvertisement adv, {
    String? macAddress,
  }) async {
    final device = DiscoveredCube(
      id: peripheral.id,
      name: peripheral.name,
      brand: CubeBrand.giiker,
      modelName: modelName(adv),
    );
    final cube = GiikerCube._(device, peripheral, GiikerParser());
    try {
      await cube._start();
    } catch (_) {
      // Handshake failed with the link open: hang up, or a retry stacks another
      // connection on top of a half-open one.
      await cube.disconnect();
      rethrow;
    }
    return cube;
  }
}

/// A connected Giiker, translating parser events into the [SmartCube] streams.
class GiikerCube implements SmartCube {
  @override
  TimingQuality get timingQuality => TimingQuality.none;

  @override
  final DiscoveredCube device;

  final BlePeripheral _peripheral;
  final GiikerParser _parser;

  final _moveCtrl = StreamController<CubeMove>.broadcast();
  final _stateCtrl = StreamController<CubeState>.broadcast();
  final _resyncCtrl = StreamController<CubeState>.broadcast();
  final _connCtrl = StreamController<CubeConnection>.broadcast();

  late final BleCharacteristic _data;
  BleCharacteristic? _batteryRead;
  BleCharacteristic? _batteryWrite;
  bool _batteryNotifying = false;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<bool>? _connSub;

  CubeState _lastState = CubeState.solved;
  CubeConnection _connection = CubeConnection.connecting;

  GiikerCube._(this.device, this._peripheral, this._parser);

  Future<void> _start() async {
    final services = await _peripheral.discoverServices();
    final dataService = services.firstWhere(
      (s) => s.uuid == normalizeUuid(GiikerDriver.dataServiceUuid),
      orElse: () => throw StateError('Giiker service not found'),
    );
    _data = dataService.characteristics.firstWhere(
      (c) => c.uuid == normalizeUuid(GiikerDriver.dataChrUuid),
      orElse: () => throw StateError('Giiker state characteristic not found'),
    );

    // Battery lives on a second service; treat it as optional so an odd
    // firmware without it still connects.
    for (final s in services) {
      if (s.uuid != normalizeUuid(GiikerDriver.rwServiceUuid)) continue;
      for (final c in s.characteristics) {
        if (c.uuid == normalizeUuid(GiikerDriver.rwReadChrUuid)) {
          _batteryRead = c;
        } else if (c.uuid == normalizeUuid(GiikerDriver.rwWriteChrUuid)) {
          _batteryWrite = c;
        }
      }
    }

    await _data.enableNotifications();
    _dataSub = _data.onValue.listen(_onData);
    _connSub = _peripheral.connected.listen((up) {
      if (!up) _setConnection(CubeConnection.lost);
    });

    // Anchor on the characteristic's current value. Best-effort: if the read
    // fails, the first turn anchors instead (every packet has the full state).
    try {
      _onData(await _data.read());
    } catch (_) {}
    _setConnection(CubeConnection.ready);
  }

  void _onData(List<int> raw) {
    for (final e in _parser.parse(raw, DateTime.now().millisecondsSinceEpoch)) {
      switch (e) {
        case GiikerStateEvent(:final state, :final isResync):
          _lastState = state;
          _stateCtrl.add(state);
          if (isResync) _resyncCtrl.add(state);
        case GiikerMoveEvent(:final move, :final stateAfter):
          _moveCtrl.add(move);
          _lastState = stateAfter;
          _stateCtrl.add(stateAfter);
      }
    }
  }

  void _setConnection(CubeConnection c) {
    _connection = c;
    if (!_connCtrl.isClosed) _connCtrl.add(c);
  }

  @override
  Stream<CubeMove> get moves => _moveCtrl.stream;

  @override
  Stream<CubeState> get states => _stateCtrl.stream;

  @override
  Stream<CubeState> get resyncs => _resyncCtrl.stream;

  @override
  Stream<CubeConnection> get connectionEvents => _connCtrl.stream;

  @override
  CubeConnection get connection => _connection;

  @override
  CubeState get currentState => _lastState;

  @override
  Future<CubeState> requestState() async {
    try {
      _onData(await _data.read());
    } catch (_) {}
    if (!_parser.needsAnchor) _lastState = _parser.currentState;
    return _lastState;
  }

  @override
  Future<void> syncState(CubeState state) async {
    _parser.setState(state);
    _lastState = state;
  }

  @override
  Future<void> resetGyro() async {
    // No gyro on this generation.
  }

  @override
  Future<int?> batteryLevel() async {
    final read = _batteryRead;
    final write = _batteryWrite;
    if (read == null || write == null) return null;
    if (!_batteryNotifying) {
      await read.enableNotifications();
      _batteryNotifying = true;
    }
    final answer = read.onValue.firstWhere((v) => v.length >= 2);
    await write.write(const [GiikerDriver.reqBattery]);
    try {
      final value = await answer.timeout(const Duration(seconds: 2));
      return value[1];
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<void> disconnect() async {
    await _dataSub?.cancel();
    await _connSub?.cancel();
    await _peripheral.disconnect();
    _setConnection(CubeConnection.disconnected);
    await _moveCtrl.close();
    await _stateCtrl.close();
    await _resyncCtrl.close();
    await _connCtrl.close();
  }
}
