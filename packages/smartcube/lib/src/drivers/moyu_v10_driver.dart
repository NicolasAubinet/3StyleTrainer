import 'dart:async';

import '../crypto/gan_cipher.dart';
import '../driver.dart';
import '../model/connection.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';
import '../smart_cube.dart';
import '../transport/ble_transport.dart';
import 'moyu_v10_parser.dart';

/// Driver for the MoYu WeiLong V10 AI (`WCU_MY32`).
class MoyuV10Driver extends CubeDriver {
  static const String serviceUuid = '0783b03e-7735-b5a0-1760-a305d2795cb0';
  static const String readChrUuid = '0783b03e-7735-b5a0-1760-a305d2795cb1';
  static const String writeChrUuid = '0783b03e-7735-b5a0-1760-a305d2795cb2';

  @override
  CubeBrand get brand => CubeBrand.moyuV10;

  @override
  List<String> get namePrefixes => const ['WCU_MY3'];

  @override
  List<String> get serviceUuids => const [serviceUuid];

  @override
  bool needsExplicitMac(CubeAdvertisement adv) => deriveMac(adv) == null;

  @override
  Future<SmartCube> connect(
    BlePeripheral peripheral,
    CubeAdvertisement adv, {
    String? macAddress,
  }) async {
    final mac = macAddress ?? deriveMac(adv);
    if (mac == null) {
      throw StateError('MoYu V10 requires a MAC address');
    }
    final device = DiscoveredCube(
      id: peripheral.id,
      name: peripheral.name,
      brand: CubeBrand.moyuV10,
    );
    final cube = MoyuV10Cube._(
      device,
      peripheral,
      MoyuV10Parser(GanCipher.macBytes(mac)),
    );
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

  /// Best-effort MAC discovery: from the device name (`WCU_MY32_XXXX` →
  /// `CF:30:16:00:XX:XX`), else from advertisement manufacturer data (last 6
  /// bytes, reversed). Returns `null` if neither is available.
  static String? deriveMac(CubeAdvertisement adv) {
    final name = adv.name ?? '';
    if (RegExp(r'^WCU_MY32_[0-9A-Fa-f]{4}$').hasMatch(name)) {
      final tail = name.substring(9).toUpperCase();
      return 'CF:30:16:00:${tail.substring(0, 2)}:${tail.substring(2, 4)}';
    }
    for (final data in adv.manufacturerData.values) {
      if (data.length >= 6) {
        return [
          for (var i = 0; i < 6; i++)
            data[data.length - i - 1].toRadixString(16).padLeft(2, '0'),
        ].join(':').toUpperCase();
      }
    }
    return null;
  }
}

/// A connected MoYu V10, translating parser events into the [SmartCube] streams.
class MoyuV10Cube implements SmartCube {
  @override
  final DiscoveredCube device;

  final BlePeripheral _peripheral;
  final MoyuV10Parser _parser;

  final _moveCtrl = StreamController<CubeMove>.broadcast();
  final _stateCtrl = StreamController<CubeState>.broadcast();
  final _resyncCtrl = StreamController<CubeState>.broadcast();
  final _connCtrl = StreamController<CubeConnection>.broadcast();

  late final BleCharacteristic _read;
  late final BleCharacteristic _write;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<bool>? _connSub;
  Timer? _anchorTimer;

  CubeState _lastState = CubeState.solved;
  CubeConnection _connection = CubeConnection.connecting;
  bool _resyncPending = false;

  MoyuV10Cube._(this.device, this._peripheral, this._parser);

  Future<void> _start() async {
    final services = await _peripheral.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == normalizeUuid(MoyuV10Driver.serviceUuid),
      orElse: () => throw StateError('MoYu V10 service not found'),
    );
    _read = service.characteristics.firstWhere(
      (c) => c.uuid == normalizeUuid(MoyuV10Driver.readChrUuid),
      orElse: () => throw StateError('MoYu V10 notify characteristic not found'),
    );
    _write = service.characteristics.firstWhere(
      (c) => c.uuid == normalizeUuid(MoyuV10Driver.writeChrUuid),
      orElse: () => throw StateError('MoYu V10 write characteristic not found'),
    );

    await _read.enableNotifications();
    _dataSub = _read.onValue.listen(_onData);
    _connSub = _peripheral.connected.listen((up) {
      if (!up) _setConnection(CubeConnection.lost);
    });

    await _write.write(_parser.encodeRequest(MoyuV10Parser.opInfo));
    await _write.write(_parser.encodeRequest(MoyuV10Parser.opStatus));
    await _write.write(_parser.encodeRequest(MoyuV10Parser.opPower));
    _setConnection(CubeConnection.ready);
  }

  void _onData(List<int> raw) {
    for (final e in _parser.parse(raw, DateTime.now().millisecondsSinceEpoch)) {
      switch (e) {
        case MoyuStateEvent(:final state):
          _lastState = state;
          _stateCtrl.add(state);
          if (_resyncPending) {
            _resyncPending = false;
            _resyncCtrl.add(state);
          }
        case MoyuMoveEvent(:final move, :final stateAfter):
          _moveCtrl.add(move);
          _lastState = stateAfter;
          _stateCtrl.add(stateAfter);
        case MoyuDesyncEvent():
          _resyncPending = true;
          _pullState();
        case MoyuBatteryEvent():
          break;
        case MoyuInfoEvent():
          break;
      }
    }
  }

  // Ask the cube for its real state. Moves stay ignored until the answer lands,
  // so keep asking until it does — a request can be lost the same way a move was.
  void _pullState() {
    _anchorTimer?.cancel();
    _write.write(_parser.encodeRequest(MoyuV10Parser.opStatus));
    _anchorTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_parser.needsAnchor || _connection != CubeConnection.ready) {
        t.cancel();
        return;
      }
      _write.write(_parser.encodeRequest(MoyuV10Parser.opStatus));
    });
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
    final answer = _stateCtrl.stream.first;
    _parser.requestPull();
    await _write.write(_parser.encodeRequest(MoyuV10Parser.opStatus));
    return answer.timeout(const Duration(seconds: 2), onTimeout: () => _lastState);
  }

  @override
  Future<void> syncState(CubeState state) async {
    _parser.setState(state);
    _lastState = state;
  }

  @override
  Future<void> resetGyro() async {
    // The V10 gyro/orientation-reset opcode is not yet reverse-engineered
    // (gyro handling is commented out in csTimer). No-op until known.
  }

  @override
  Future<int?> batteryLevel() async {
    await _write.write(_parser.encodeRequest(MoyuV10Parser.opPower));
    return _parser.batteryLevel;
  }

  @override
  Future<void> disconnect() async {
    _anchorTimer?.cancel();
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
