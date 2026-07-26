import 'dart:async';

import '../crypto/gan_cipher.dart';
import '../driver.dart';
import '../model/connection.dart';
import '../model/cube_error.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';
import '../reconstruct/timing_quality.dart';
import '../smart_cube.dart';
import '../transport/ble_transport.dart';
import 'moyu_v10_parser.dart';

/// Driver for the MoYu WeiLong V10 AI (`WCU_MY32`). Claims the whole
/// `WCU_MY3x` name family, so a WeiLong V11 (an uncharted `WCU_MY3x`) routes
/// here too: if it shares the V10 service + protocol it just works (see
/// [deriveMac] for the MAC handling); a different service fails loudly at
/// [MoyuV10Cube._start]. See the V11 triage in docs/smart-cube-integration-plan.md §29.
class MoyuV10Driver extends CubeDriver {
  static const String serviceUuid = '0783b03e-7735-b5a0-1760-a305d2795cb0';
  static const String readChrUuid = '0783b03e-7735-b5a0-1760-a305d2795cb1';
  static const String writeChrUuid = '0783b03e-7735-b5a0-1760-a305d2795cb2';

  /// How long the handshake waits for a decodable answer before blaming the MAC.
  /// Overridable so tests need not wait out the real one.
  final Duration macProbeTimeout;

  MoyuV10Driver({this.macProbeTimeout = defaultMacProbeTimeout});

  @override
  CubeBrand get brand => CubeBrand.moyuV10;

  @override
  List<String> get namePrefixes => const ['WCU_MY3'];

  @override
  List<String> get serviceUuids => const [serviceUuid];

  @override
  bool needsExplicitMac(CubeAdvertisement adv) => deriveMac(adv) == null;

  static const String _v10Oui = 'CF:30:16:00';
  static const String _v11Oui = 'CF:30:16:02';

  /// V10 and V11 advertise the same `WCU_MY32` name; only the MAC OUI tells
  /// them apart (V10 `CF:30:16:00`, V11 `CF:30:16:02` — both hardware-confirmed).
  @override
  String? modelName(CubeAdvertisement adv) {
    final mac = deriveMac(adv);
    if (mac != null && mac.startsWith(_v11Oui)) return 'MoYu WeiLong V11';
    if (mac != null && mac.startsWith(_v10Oui)) return 'MoYu WeiLong V10';
    return 'MoYu WeiLong V10/V11';
  }

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
      modelName: modelName(adv),
      macAddress: mac,
    );
    final cube = MoyuV10Cube._(
      device,
      peripheral,
      MoyuV10Parser(GanCipher.macBytes(mac)),
      macProbeTimeout,
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

  /// Matches the `WCU_MY3x_XXXX` name family (V10 is `WCU_MY32`; a V11 is
  /// expected to be another `WCU_MY3x`). Group 1 is the model token, group 2 the
  /// 4 hex MAC-tail characters.
  static final RegExp _namePattern =
      RegExp(r'^WCU_(MY3[0-9])_([0-9A-Fa-f]{4})$');

  /// Model tokens whose MAC OUI we have actually confirmed, for the name-derived
  /// fallback. ⚠ The V11 advertises the *same* `WCU_MY32` token but a
  /// `CF:30:16:02` OUI (hardware-confirmed 2026-07-22), so the name alone cannot
  /// distinguish the two — the table maps the token to the V10 OUI only as a
  /// last resort where manufacturer data is unavailable (web).
  static const Map<String, String> _knownOuis = {'MY32': _v10Oui};

  static final RegExp _macPattern =
      RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');

  /// Best-effort MAC discovery: (1) advertisement manufacturer data (last 6
  /// bytes, reversed) — the cube's real MAC for any model; (2) the device id,
  /// on platforms where it is the MAC (Windows, Android, Linux); (3) name-derived
  /// (`WCU_MY32_XXXX` → `CF:30:16:00:XX:XX`), works even on web; (4) `null` →
  /// the caller prompts for a manual MAC. The real-MAC sources win because the
  /// name-derived OUI only holds for the V10: the V11 shares the `WCU_MY32`
  /// name family but not the OUI, and a wrong MAC yields a wrong cipher key —
  /// the cube "connects" and every packet decodes to garbage.
  static String? deriveMac(CubeAdvertisement adv) {
    for (final data in adv.manufacturerData.values) {
      if (data.length >= 6) {
        return [
          for (var i = 0; i < 6; i++)
            data[data.length - i - 1].toRadixString(16).padLeft(2, '0'),
        ].join(':').toUpperCase();
      }
    }
    if (_macPattern.hasMatch(adv.id)) return adv.id.toUpperCase();
    final match = _namePattern.firstMatch(adv.name ?? '');
    if (match != null) {
      final oui = _knownOuis[match.group(1)];
      if (oui != null) {
        final tail = match.group(2)!.toUpperCase();
        return '$oui:${tail.substring(0, 2)}:${tail.substring(2, 4)}';
      }
    }
    return null;
  }
}

/// A connected MoYu V10, translating parser events into the [SmartCube] streams.
class MoyuV10Cube implements SmartCube {
  @override
  TimingQuality get timingQuality => TimingQuality.perMoveClock;

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

  final Duration _macProbeTimeout;

  MoyuV10Cube._(
      this.device, this._peripheral, this._parser, this._macProbeTimeout);

  Future<void> _start() async {
    final services = await _peripheral.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == normalizeUuid(MoyuV10Driver.serviceUuid),
      orElse: () => throw StateError(
          'MoYu V10 service not found (a V11 may use a different service UUID)'),
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
    await _awaitAnchor();
    await _write.write(_parser.encodeRequest(MoyuV10Parser.opPower));
    _setConnection(CubeConnection.ready);
  }

  /// Ask for the cube's state until it answers with one that decodes. The key
  /// comes from the MAC, so a wrong MAC leaves the link up while every packet
  /// decodes to noise — this is where that gets caught, rather than handing back
  /// a cube that never reports a move.
  Future<void> _awaitAnchor() async {
    if (!_parser.needsAnchor) return;
    final anchored = Completer<void>();
    final sub = _stateCtrl.stream.listen((_) {
      if (!anchored.isCompleted) anchored.complete();
    });
    // A request can be lost the same way a move can, so keep asking — but not
    // into a link that already dropped, which would only raise write after
    // failed write until the timeout.
    final retry = Timer.periodic(anchorRetryInterval, (t) {
      if (_connection == CubeConnection.lost) {
        t.cancel();
        return;
      }
      _write.write(_parser.encodeRequest(MoyuV10Parser.opStatus));
    });
    try {
      await _write.write(_parser.encodeRequest(MoyuV10Parser.opStatus));
      await anchored.future.timeout(_macProbeTimeout);
    } on TimeoutException {
      throw CubeMacRejectedException(device.macAddress ?? '?');
    } finally {
      retry.cancel();
      await sub.cancel();
    }
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
    _anchorTimer = Timer.periodic(anchorRetryInterval, (t) {
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
