import 'dart:async';

import '../driver.dart';
import '../reconstruct/move_prior.dart';
import '../model/connection.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';
import '../smart_cube.dart';
import '../transport/ble_transport.dart';
import 'gocube_parser.dart';

/// Driver for GoCube and Rubik's Connected (a GoCube rebadge), which speak the
/// same unencrypted Nordic-UART protocol. No MAC, no crypto, no handshake — the
/// cube streams moves on its own; the app only asks for the initial state.
class GoCubeDriver extends CubeDriver {
  // GoCube discards the per-move duration byte and batches moves into one
  // notification, so turns in the same packet share a timestamp (see the
  // GoCube protocol notes). There is no usable per-move clock.
  @override
  TimingQuality get timingQuality => TimingQuality.none;

  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String writeChrUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String readChrUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  @override
  CubeBrand get brand => CubeBrand.gocube;

  @override
  List<String> get namePrefixes => const ['GoCube', 'Rubiks'];

  @override
  List<String> get serviceUuids => const [serviceUuid];

  @override
  Future<SmartCube> connect(
    BlePeripheral peripheral,
    CubeAdvertisement adv, {
    String? macAddress,
  }) async {
    final device = DiscoveredCube(
      id: peripheral.id,
      name: peripheral.name,
      brand: CubeBrand.gocube,
    );
    final cube = GoCubeCube._(device, peripheral, GoCubeParser());
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

/// A connected GoCube, translating parser events into the [SmartCube] streams.
class GoCubeCube implements SmartCube {
  @override
  TimingQuality get timingQuality => TimingQuality.none;

  /// GoCube carries no move counter, so a dropped notification can't be seen per
  /// packet — only a fresh state can catch the drift. Re-request state every this
  /// many moves to bound how far the model can wander (csTimer's rule).
  static const int _resyncEvery = 20;

  @override
  final DiscoveredCube device;

  final BlePeripheral _peripheral;
  final GoCubeParser _parser;

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
  int _movesSinceState = 0;

  GoCubeCube._(this.device, this._peripheral, this._parser);

  Future<void> _start() async {
    final services = await _peripheral.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == normalizeUuid(GoCubeDriver.serviceUuid),
      orElse: () => throw StateError('GoCube service not found'),
    );
    _read = service.characteristics.firstWhere(
      (c) => c.uuid == normalizeUuid(GoCubeDriver.readChrUuid),
      orElse: () => throw StateError('GoCube notify characteristic not found'),
    );
    _write = service.characteristics.firstWhere(
      (c) => c.uuid == normalizeUuid(GoCubeDriver.writeChrUuid),
      orElse: () => throw StateError('GoCube write characteristic not found'),
    );

    await _read.enableNotifications();
    _dataSub = _read.onValue.listen(_onData);
    _connSub = _peripheral.connected.listen((up) {
      if (!up) _setConnection(CubeConnection.lost);
    });

    await _write.write(_parser.encodeRequestBattery());
    _setConnection(CubeConnection.ready);
    _pullState();
  }

  // Moves stay dropped until the first state anchors the model, so keep asking
  // for it — the request can be lost the same way a notification can.
  void _pullState() {
    _anchorTimer?.cancel();
    _write.write(_parser.encodeRequestState()).catchError((_) {});
    _anchorTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_parser.needsAnchor || _connection != CubeConnection.ready) {
        t.cancel();
        return;
      }
      _write.write(_parser.encodeRequestState()).catchError((_) {});
    });
  }

  void _onData(List<int> raw) {
    for (final e in _parser.parse(raw, DateTime.now().millisecondsSinceEpoch)) {
      switch (e) {
        case GoCubeStateEvent(:final state, :final isResync):
          _movesSinceState = 0;
          _lastState = state;
          _stateCtrl.add(state);
          if (isResync) _resyncCtrl.add(state);
        case GoCubeMoveEvent(:final move, :final stateAfter):
          _moveCtrl.add(move);
          _lastState = stateAfter;
          _stateCtrl.add(stateAfter);
          if (++_movesSinceState >= _resyncEvery) {
            _movesSinceState = 0;
            _write.write(_parser.encodeRequestState()).catchError((_) {});
          }
        case GoCubeBatteryEvent():
          break;
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
    final answer = _stateCtrl.stream.first;
    await _write.write(_parser.encodeRequestState());
    return answer.timeout(const Duration(seconds: 2), onTimeout: () => _lastState);
  }

  @override
  Future<void> syncState(CubeState state) async {
    _parser.setState(state);
    _lastState = state;
  }

  @override
  Future<void> resetGyro() async {
    // GoCube reports orientation (message type 3) but the trainer doesn't track
    // it, and no orientation-reset opcode is documented. No-op.
  }

  @override
  Future<int?> batteryLevel() async {
    await _write.write(_parser.encodeRequestBattery());
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
