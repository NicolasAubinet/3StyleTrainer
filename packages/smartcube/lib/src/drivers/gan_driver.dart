import 'dart:async';

import '../crypto/gan_cipher.dart';
import '../driver.dart';
import '../model/connection.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';
import '../smart_cube.dart';
import '../transport/ble_transport.dart';
import 'gan_gen2_parser.dart';

/// Driver for GAN Gen2 smart cubes (GAN 356 i3, i Carry / i Carry S, GAN12 ui,
/// GAN Mini ui FreePlay, Monster Go 3Ai) and the MoYu AI 2023, which speaks the
/// same protocol under the `AiCube` name.
///
/// Gen3 (`GAN 356 i Carry 2`) and Gen4 (`GAN12 ui Maglev`, `GAN14 ui FreePlay`)
/// advertise the same names but different services; they are rejected at connect
/// with a clear message rather than half-supported.
class GanDriver extends CubeDriver {
  static const String gen2Service = '6e400001-b5a3-f393-e0a9-e50e24dc4179';
  static const String gen2CommandChrUuid =
      '28be4a4a-cd67-11e9-a32f-2a2ae2dbcce4';
  static const String gen2StateChrUuid = '28be4cb6-cd67-11e9-a32f-2a2ae2dbcce4';

  static const String gen3Service = '8653000a-43e6-47b7-9cb0-5fc21d4ae340';
  static const String gen4Service = '00000010-0000-fff7-fff6-fff5fff4fff0';

  @override
  CubeBrand get brand => CubeBrand.gan;

  @override
  List<String> get namePrefixes => const ['GAN', 'MG', 'AiCube'];

  @override
  List<String> get serviceUuids => const [gen2Service, gen3Service, gen4Service];

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
      throw StateError('GAN cubes require a MAC address');
    }
    final device = DiscoveredCube(
      id: peripheral.id,
      name: peripheral.name,
      brand: CubeBrand.gan,
    );
    // The MoYu AI 2023 is a Gen2 cube with its own key.
    final moyuAi = (adv.name ?? peripheral.name).startsWith('AiCube');
    final cube = GanCube._(
      device,
      peripheral,
      GanGen2Parser(GanCipher.macBytes(mac), moyuAi: moyuAi),
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

  /// The MAC lives in the last 6 bytes (reversed) of the first 9 bytes of the
  /// manufacturer data, under a GAN company identifier — every code of the form
  /// `0xNN01`. Returns `null` when the platform hides it (web), leaving the
  /// caller to ask the user.
  static String? deriveMac(CubeAdvertisement adv) {
    for (final entry in adv.manufacturerData.entries) {
      if (entry.key & 0xFF != 0x01) continue;
      final data = entry.value.length > 9
          ? entry.value.sublist(0, 9)
          : entry.value;
      if (data.length < 6) continue;
      return [
        for (var i = 1; i <= 6; i++)
          data[data.length - i].toRadixString(16).padLeft(2, '0'),
      ].join(':').toUpperCase();
    }
    return null;
  }
}

/// A connected GAN cube, translating parser events into the [SmartCube] streams.
class GanCube implements SmartCube {
  @override
  final DiscoveredCube device;

  final BlePeripheral _peripheral;
  final GanGen2Parser _parser;

  final _moveCtrl = StreamController<CubeMove>.broadcast();
  final _stateCtrl = StreamController<CubeState>.broadcast();
  final _resyncCtrl = StreamController<CubeState>.broadcast();
  final _connCtrl = StreamController<CubeConnection>.broadcast();

  late final BleCharacteristic _state;
  late final BleCharacteristic _command;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<bool>? _connSub;
  Timer? _anchorTimer;

  CubeState _lastState = CubeState.solved;
  CubeConnection _connection = CubeConnection.connecting;
  bool _resyncPending = false;

  GanCube._(this.device, this._peripheral, this._parser);

  Future<void> _start() async {
    final services = await _peripheral.discoverServices();
    final gen2 = normalizeUuid(GanDriver.gen2Service);
    final service = services.firstWhere(
      (s) => s.uuid == gen2,
      orElse: () {
        final uuids = services.map((s) => s.uuid).toSet();
        if (uuids.contains(normalizeUuid(GanDriver.gen3Service)) ||
            uuids.contains(normalizeUuid(GanDriver.gen4Service))) {
          throw StateError(
              'This GAN cube speaks the Gen3/Gen4 protocol, which is not supported yet');
        }
        throw StateError('GAN Gen2 service not found');
      },
    );
    _command = service.characteristics.firstWhere(
      (c) => c.uuid == normalizeUuid(GanDriver.gen2CommandChrUuid),
      orElse: () => throw StateError('GAN command characteristic not found'),
    );
    _state = service.characteristics.firstWhere(
      (c) => c.uuid == normalizeUuid(GanDriver.gen2StateChrUuid),
      orElse: () => throw StateError('GAN state characteristic not found'),
    );

    await _state.enableNotifications();
    _dataSub = _state.onValue.listen(_onData);
    _connSub = _peripheral.connected.listen((up) {
      if (!up) _setConnection(CubeConnection.lost);
    });

    await _command.write(_parser.encodeRequest(GanGen2Parser.opHardware));
    await _command.write(_parser.encodeRequest(GanGen2Parser.opBattery));
    // Moves are ignored until this lands and anchors the model.
    await _command.write(_parser.encodeRequest(GanGen2Parser.opFacelets));
    _setConnection(CubeConnection.ready);
  }

  void _onData(List<int> raw) {
    for (final e in _parser.parse(raw, DateTime.now().millisecondsSinceEpoch)) {
      switch (e) {
        case GanStateEvent(:final state):
          _lastState = state;
          _stateCtrl.add(state);
          if (_resyncPending) {
            _resyncPending = false;
            _resyncCtrl.add(state);
          }
        case GanMoveEvent(:final move, :final stateAfter):
          _moveCtrl.add(move);
          _lastState = stateAfter;
          _stateCtrl.add(stateAfter);
        case GanDesyncEvent():
          _resyncPending = true;
          _pullState();
        case GanDisconnectEvent():
          _setConnection(CubeConnection.lost);
        case GanBatteryEvent():
          break;
        case GanInfoEvent():
          break;
      }
    }
  }

  // Ask the cube for its real state. Moves stay ignored until the answer lands,
  // so keep asking until it does — a request can be lost the same way a move was.
  void _pullState() {
    _anchorTimer?.cancel();
    _command.write(_parser.encodeRequest(GanGen2Parser.opFacelets));
    _anchorTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_parser.needsAnchor || _connection != CubeConnection.ready) {
        t.cancel();
        return;
      }
      _command.write(_parser.encodeRequest(GanGen2Parser.opFacelets));
    });
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

  void _setConnection(CubeConnection c) {
    _connection = c;
    if (!_connCtrl.isClosed) _connCtrl.add(c);
  }

  @override
  Future<CubeState> requestState() async {
    final answer = _stateCtrl.stream.first;
    // Keep the anchor: if the cube is being turned while the pull is in flight,
    // the snapshot lands stale and is dropped, and the tracked model — which is
    // still following those moves — is the better answer anyway.
    await _command.write(_parser.encodeRequest(GanGen2Parser.opFacelets));
    return answer.timeout(const Duration(seconds: 2), onTimeout: () => _lastState);
  }

  @override
  Future<void> syncState(CubeState state) async {
    // Unlike the V10, a GAN cube tracks state in its own firmware, so a local-only
    // realign would be undone by its next facelets. Solved is the one state it can
    // be told to adopt; anything else can only move the model here.
    if (state.isSolved) {
      await _command.write(_parser.encodeReset());
    }
    _parser.setState(state);
    _lastState = state;
  }

  @override
  Future<void> resetGyro() async {
    // Gen2 exposes no gyro-reset opcode, and the trainer takes orientation from
    // a setting rather than the gyro. No-op.
  }

  @override
  Future<int?> batteryLevel() async {
    await _command.write(_parser.encodeRequest(GanGen2Parser.opBattery));
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
