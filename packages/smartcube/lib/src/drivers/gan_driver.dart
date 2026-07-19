import 'dart:async';

import '../crypto/gan_cipher.dart';
import '../driver.dart';
import '../model/connection.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';
import '../reconstruct/move_prior.dart';
import '../smart_cube.dart';
import '../transport/ble_transport.dart';
import 'gan_gen2_parser.dart';
import 'gan_gen3_parser.dart';
import 'gan_gen4_parser.dart';
import 'gan_protocol.dart';

/// One GAN protocol generation, and how to recognise and speak it.
class GanGeneration {
  final String service;
  final String commandChrUuid;
  final String stateChrUuid;
  final GanProtocol Function(List<int> mac, {required bool moyuAi}) build;

  const GanGeneration({
    required this.service,
    required this.commandChrUuid,
    required this.stateChrUuid,
    required this.build,
  });
}

/// Driver for GAN smart cubes. The generation is not something the user picks —
/// every GAN cube advertises the same names, so the protocol is chosen from
/// whichever service the cube turns out to expose:
///
/// - **Gen2** — GAN 356 i3, i Carry / i Carry S, GAN12 ui, Mini ui FreePlay,
///   Monster Go 3Ai, and the MoYu AI 2023 (`AiCube`, same protocol, own key).
/// - **Gen3** — GAN 356 i Carry 2.
/// - **Gen4** — GAN12 ui Maglev, GAN14 ui FreePlay.
class GanDriver extends CubeDriver {
  static const String gen2Service = '6e400001-b5a3-f393-e0a9-e50e24dc4179';
  static const String gen2CommandChrUuid =
      '28be4a4a-cd67-11e9-a32f-2a2ae2dbcce4';
  static const String gen2StateChrUuid = '28be4cb6-cd67-11e9-a32f-2a2ae2dbcce4';

  static const String gen3Service = '8653000a-43e6-47b7-9cb0-5fc21d4ae340';
  static const String gen3CommandChrUuid =
      '8653000c-43e6-47b7-9cb0-5fc21d4ae340';
  static const String gen3StateChrUuid = '8653000b-43e6-47b7-9cb0-5fc21d4ae340';

  static const String gen4Service = '00000010-0000-fff7-fff6-fff5fff4fff0';
  static const String gen4CommandChrUuid =
      '0000fff5-0000-1000-8000-00805f9b34fb';
  static const String gen4StateChrUuid = '0000fff6-0000-1000-8000-00805f9b34fb';

  /// Tried in order against the cube's advertised services.
  static final List<GanGeneration> generations = [
    GanGeneration(
      service: gen2Service,
      commandChrUuid: gen2CommandChrUuid,
      stateChrUuid: gen2StateChrUuid,
      build: (mac, {required moyuAi}) => GanGen2Parser(mac, moyuAi: moyuAi),
    ),
    GanGeneration(
      service: gen3Service,
      commandChrUuid: gen3CommandChrUuid,
      stateChrUuid: gen3StateChrUuid,
      build: (mac, {required moyuAi}) => GanGen3Parser(mac),
    ),
    GanGeneration(
      service: gen4Service,
      commandChrUuid: gen4CommandChrUuid,
      stateChrUuid: gen4StateChrUuid,
      build: (mac, {required moyuAi}) => GanGen4Parser(mac),
    ),
  ];

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
    final cube = GanCube._(
      device,
      peripheral,
      GanCipher.macBytes(mac),
      // The MoYu AI 2023 is a Gen2 cube with its own key.
      moyuAi: (adv.name ?? peripheral.name).startsWith('AiCube'),
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
      final data =
          entry.value.length > 9 ? entry.value.sublist(0, 9) : entry.value;
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
  TimingQuality get timingQuality => TimingQuality.perMoveClock;

  @override
  final DiscoveredCube device;

  final BlePeripheral _peripheral;
  final List<int> _mac;
  final bool _moyuAi;

  final _moveCtrl = StreamController<CubeMove>.broadcast();
  final _stateCtrl = StreamController<CubeState>.broadcast();
  final _resyncCtrl = StreamController<CubeState>.broadcast();
  final _connCtrl = StreamController<CubeConnection>.broadcast();

  late final GanProtocol _protocol;
  late final BleCharacteristic _state;
  late final BleCharacteristic _command;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<bool>? _connSub;
  Timer? _anchorTimer;

  CubeState _lastState = CubeState.solved;
  CubeConnection _connection = CubeConnection.connecting;
  bool _resyncPending = false;

  GanCube._(this.device, this._peripheral, this._mac, {required bool moyuAi})
      : _moyuAi = moyuAi;

  Future<void> _start() async {
    final services = await _peripheral.discoverServices();
    final byUuid = {for (final s in services) s.uuid: s};

    final generation = GanDriver.generations
        .where((g) => byUuid.containsKey(normalizeUuid(g.service)))
        .firstOrNull;
    if (generation == null) {
      throw StateError('No supported GAN service found');
    }

    final service = byUuid[normalizeUuid(generation.service)]!;
    _command = service.characteristics.firstWhere(
      (c) => c.uuid == normalizeUuid(generation.commandChrUuid),
      orElse: () => throw StateError('GAN command characteristic not found'),
    );
    _state = service.characteristics.firstWhere(
      (c) => c.uuid == normalizeUuid(generation.stateChrUuid),
      orElse: () => throw StateError('GAN state characteristic not found'),
    );
    _protocol = generation.build(_mac, moyuAi: _moyuAi);

    await _state.enableNotifications();
    _dataSub = _state.onValue.listen(_onData);
    _connSub = _peripheral.connected.listen((up) {
      if (!up) _setConnection(CubeConnection.lost);
    });

    await _request(GanRequest.hardware);
    await _request(GanRequest.battery);
    // Moves are ignored until this lands and anchors the model.
    await _request(GanRequest.facelets);
    _setConnection(CubeConnection.ready);
  }

  Future<void> _request(GanRequest request) async {
    final msg = _protocol.encodeRequest(request);
    if (msg != null) await _command.write(msg);
  }

  void _onData(List<int> raw) {
    for (final e in _protocol.parse(raw, DateTime.now().millisecondsSinceEpoch)) {
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
        case GanHistoryRequestEvent(:final serial, :final count):
          final msg = _protocol.encodeMoveHistory(serial, count);
          // A write that fails is not worth reacting to: the next move event
          // re-detects the same gap and asks again.
          if (msg != null) _command.write(msg).catchError((_) {});
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
    _request(GanRequest.facelets);
    _anchorTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_protocol.needsAnchor || _connection != CubeConnection.ready) {
        t.cancel();
        return;
      }
      _request(GanRequest.facelets);
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
    await _request(GanRequest.facelets);
    return answer.timeout(const Duration(seconds: 2), onTimeout: () => _lastState);
  }

  @override
  Future<void> syncState(CubeState state) async {
    // Unlike the V10, a GAN cube tracks state in its own firmware, so a local-only
    // realign would be undone by its next facelets. Solved is the one state it can
    // be told to adopt; anything else can only move the model here.
    if (state.isSolved) {
      await _request(GanRequest.reset);
    }
    _protocol.setState(state);
    _lastState = state;
  }

  @override
  Future<void> resetGyro() async {
    // No GAN generation exposes a gyro-reset opcode, and the trainer takes
    // orientation from a setting rather than the gyro. No-op.
  }

  @override
  Future<int?> batteryLevel() async {
    await _request(GanRequest.battery);
    return _protocol.batteryLevel;
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
