import 'dart:async';

import '../driver.dart';
import '../model/connection.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';
import '../smart_cube.dart';
import '../transport/ble_transport.dart';
import 'qiyi_parser.dart';

/// Driver for the QiYi Smart Cube (`QY-QYSC`) and the Tornado V4
/// (`XMD-TornadoV4-i`), which speaks the same protocol.
class QiyiDriver extends CubeDriver {
  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';

  /// One characteristic for both write and notify, unlike every other brand.
  static const String chrUuid = '0000fff6-0000-1000-8000-00805f9b34fb';

  /// Company identifier the MAC hides under when the name doesn't carry it.
  static const int manufacturerCic = 0x0504;

  static final RegExp _nameMac =
      RegExp(r'^(?:QY-QYSC|XMD-TornadoV4-i)-.-([0-9A-Fa-f]{4})$');

  @override
  CubeBrand get brand => CubeBrand.qiyi;

  @override
  List<String> get namePrefixes => const ['QY-QYSC', 'XMD-TornadoV4-i'];

  /// Deliberately empty. QiYi's `0000fff0` service is the **same UUID GAN Gen1
  /// advertises**, so claiming it would let this driver swallow GAN cubes. The
  /// names disambiguate; nameless QiYi devices are not worth that risk.
  @override
  List<String> get serviceUuids => const [];

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
      // The key is fixed, but the App Hello carries the MAC and the cube stays
      // silent without it — so this is as mandatory as it is on GAN.
      throw StateError('QiYi cubes require a MAC address');
    }
    final device = DiscoveredCube(
      id: peripheral.id,
      name: peripheral.name,
      brand: CubeBrand.qiyi,
    );
    final cube = QiyiCube._(device, peripheral, QiyiParser(macBytes(mac)));
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

  /// From the device name (`QY-QYSC-X-XXXX` → `CC:A3:00:00:XX:XX`), else from
  /// advertisement manufacturer data — the **first** 6 bytes, reversed (GAN's
  /// last-6-of-first-9 rule does *not* apply here). `null` when the platform
  /// hides both (web), leaving the caller to ask the user.
  static String? deriveMac(CubeAdvertisement adv) {
    final tail = _nameMac.firstMatch(adv.name ?? '')?.group(1);
    if (tail != null) {
      final t = tail.toUpperCase();
      return 'CC:A3:00:00:${t.substring(0, 2)}:${t.substring(2, 4)}';
    }
    final data = adv.manufacturerData[manufacturerCic];
    if (data != null && data.length >= 6) {
      return [
        for (var i = 5; i >= 0; i--) data[i].toRadixString(16).padLeft(2, '0'),
      ].join(':').toUpperCase();
    }
    return null;
  }

  /// Parse a MAC string like `CC:A3:00:00:AB:CD` into its 6 bytes.
  static List<int> macBytes(String mac) => [
        for (var i = 0; i < 6; i++)
          int.parse(mac.substring(i * 3, i * 3 + 2), radix: 16),
      ];
}

/// A connected QiYi cube, translating parser events into the [SmartCube]
/// streams.
class QiyiCube implements SmartCube {
  @override
  final DiscoveredCube device;

  final BlePeripheral _peripheral;
  final QiyiParser _parser;

  final _moveCtrl = StreamController<CubeMove>.broadcast();
  final _stateCtrl = StreamController<CubeState>.broadcast();
  final _resyncCtrl = StreamController<CubeState>.broadcast();
  final _connCtrl = StreamController<CubeConnection>.broadcast();

  late final BleCharacteristic _chr;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<bool>? _connSub;
  Timer? _helloTimer;

  CubeState _lastState = CubeState.solved;
  CubeConnection _connection = CubeConnection.connecting;
  bool _greeted = false;

  QiyiCube._(this.device, this._peripheral, this._parser);

  Future<void> _start() async {
    final services = await _peripheral.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == normalizeUuid(QiyiDriver.serviceUuid),
      orElse: () => throw StateError('QiYi service not found'),
    );
    _chr = service.characteristics.firstWhere(
      (c) => c.uuid == normalizeUuid(QiyiDriver.chrUuid),
      orElse: () => throw StateError('QiYi characteristic not found'),
    );

    await _chr.enableNotifications();
    _dataSub = _chr.onValue.listen(_onData);
    _connSub = _peripheral.connected.listen((up) {
      if (!up) _setConnection(CubeConnection.lost);
    });

    await _chr.write(_parser.encodeAppHello());
    _setConnection(CubeConnection.ready);
    _keepSayingHello();
  }

  // The cube reports nothing until it has been greeted, so a lost hello write is
  // a permanently dead connection rather than one missed packet. Keep saying it
  // until the cube says hello back.
  void _keepSayingHello() {
    _helloTimer?.cancel();
    _helloTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_greeted || _connection != CubeConnection.ready) {
        t.cancel();
        return;
      }
      _chr.write(_parser.encodeAppHello()).catchError((_) {});
    });
  }

  void _onData(List<int> raw) {
    for (final e in _parser.parse(raw, DateTime.now().millisecondsSinceEpoch)) {
      switch (e) {
        case QiyiAckRequestEvent(:final message):
          // A failed ACK is not worth reacting to — the cube re-sends.
          _chr.write(message).catchError((_) {});
        case QiyiHelloEvent(:final state):
          _greeted = true;
          _helloTimer?.cancel();
          _lastState = state;
          _stateCtrl.add(state);
        case QiyiStateEvent(:final state):
          _lastState = state;
          _stateCtrl.add(state);
        case QiyiMoveEvent(:final move, :final stateAfter):
          _moveCtrl.add(move);
          _lastState = stateAfter;
          _stateCtrl.add(stateAfter);
        case QiyiBatteryEvent():
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

  /// Never fires. Every state change carries the cube's own full state, so the
  /// model cannot drift out of sync the way a move-tracked one does (§21) — a
  /// dropped notification costs one move event and the next packet re-states the
  /// truth. There is nothing to re-anchor and no baseline to retake.
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
    await _chr.write(_parser.encodeRequestState());
    return answer.timeout(const Duration(seconds: 2),
        onTimeout: () => _lastState);
  }

  @override
  Future<void> syncState(CubeState state) async {
    // Nothing to realign: no local model is integrated here, and the cube's next
    // state change overwrites whatever is set. (Its own sync opcode is not in
    // the spec we ported — Sync Confirmation is only ever seen as the reply.)
    _lastState = state;
  }

  @override
  Future<void> resetGyro() async {
    // The QiYi cube has no gyro.
  }

  @override
  Future<int?> batteryLevel() async {
    // There is no battery request: the level rides along on the cube hello and
    // on every state change, so the cached value is as fresh as the last turn.
    return _parser.batteryLevel;
  }

  @override
  Future<void> disconnect() async {
    _helloTimer?.cancel();
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
