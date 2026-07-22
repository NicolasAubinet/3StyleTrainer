import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:smartcube/src/drivers/giiker_driver.dart';
import 'package:smartcube/src/drivers/giiker_parser.dart';

/// End-to-end through a fake transport: scan → connect → decode. Giiker needs
/// no MAC and no handshake; the initial state comes from a GATT read of the
/// state characteristic. Packets are synthetic (no hardware capture yet) —
/// built by inverting the decoder through its own facelet tables.
void main() {
  const coMask = [-1, 1, -1, 1, 1, -1, 1, -1];

  String colour(int home) => 'URFDLB'[home ~/ 9];

  List<int> packet(String facelets, List<(int, int)> history) {
    final hex = List<int>.filled(32, 0, growable: true);
    for (var g = 0; g < 8; g++) {
      for (var p = 0; p < 8; p++) {
        for (var o = 0; o < 3; o++) {
          var ok = true;
          for (var n = 0; n < 3 && ok; n++) {
            ok = facelets[GiikerParser.cFacelet[g][(n + o) % 3]] ==
                colour(GiikerParser.cFacelet[p][n]);
          }
          if (ok) {
            hex[g] = p + 1;
            hex[g + 8] = coMask[g] == 1 ? o : (3 - o) % 3;
          }
        }
      }
    }
    for (var g = 0; g < 12; g++) {
      for (var p = 0; p < 12; p++) {
        for (var o = 0; o < 2; o++) {
          var ok = true;
          for (var n = 0; n < 2 && ok; n++) {
            ok = facelets[GiikerParser.eFacelet[g][(n + o) % 2]] ==
                colour(GiikerParser.eFacelet[p][n]);
          }
          if (ok) {
            hex[16 + g] = p + 1;
            if (o == 1) hex[28 + g ~/ 4] |= 1 << (3 - g % 4);
          }
        }
      }
    }
    for (var k = 0; k < 4; k++) {
      final (face, dir) = k < history.length ? history[k] : (1, 1);
      hex.addAll([face, dir]);
    }
    return [
      for (var i = 0; i < hex.length; i += 2) hex[i] << 4 | hex[i + 1],
    ];
  }

  String afterMoves(List<(Face, bool)> moves) {
    final c = CubieCube();
    for (final (face, prime) in moves) {
      c.applyMove(face, prime);
    }
    return c.toFaceCube();
  }

  ({
    _FakeChr data,
    _FakeChr batteryRead,
    _FakeChr batteryWrite,
    CubeScanner scanner
  }) rig({String name = 'Gi-i3-ABC'}) {
    final data = _FakeChr(normalizeUuid(GiikerDriver.dataChrUuid))
      ..readValue = packet(CubieCube.solvedFacelet, const []);
    final batteryRead = _FakeChr(normalizeUuid(GiikerDriver.rwReadChrUuid));
    final batteryWrite = _FakeChr(normalizeUuid(GiikerDriver.rwWriteChrUuid));
    final peripheral = _FakePeripheral('dev1', name, [
      _FakeService(normalizeUuid(GiikerDriver.dataServiceUuid), [data]),
      _FakeService(
          normalizeUuid(GiikerDriver.rwServiceUuid), [batteryRead, batteryWrite]),
    ]);
    final transport = _FakeTransport(
      peripheral,
      BleScanResult(deviceId: 'dev1', name: name),
    );
    return (
      data: data,
      batteryRead: batteryRead,
      batteryWrite: batteryWrite,
      scanner: createCubeScanner(transport: transport),
    );
  }

  test('scan discovers Giiker and Xiaomi names, needing no MAC', () async {
    final giiker = await rig().scanner.scan().first;
    expect(giiker.brand, CubeBrand.giiker);
    expect(giiker.needsMac, isFalse);

    final mi = await rig(name: 'Mi Smart Magic Cube').scanner.scan().first;
    expect(mi.brand, CubeBrand.giiker);
    expect(mi.modelName, 'Mi Smart Magic Cube');

    final hi = await rig(name: 'Hi-XYZ').scanner.scan().first;
    expect(hi.brand, CubeBrand.giiker);
  });

  test('connect anchors from a GATT read, then decodes turns', () async {
    final r = rig();
    final cube = await r.scanner.connect(await r.scanner.scan().first);
    expect(cube.connection, CubeConnection.ready);
    expect(cube.currentState, CubeState.solved);

    final moves = <CubeMove>[];
    cube.moves.listen(moves.add);
    final afterU = afterMoves(const [(Face.U, false)]);
    r.data.push(packet(afterU, const [(4, 1)]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(moves.single.face, Face.U);
    expect(moves.single.prime, isFalse);
    expect(cube.currentState.facelets, afterU);
    await cube.disconnect();
  });

  test('an unexplainable state fires a resync', () async {
    final r = rig();
    final cube = await r.scanner.connect(await r.scanner.scan().first);
    final resyncs = <CubeState>[];
    cube.resyncs.listen(resyncs.add);

    final far = afterMoves(const [(Face.L, false), (Face.F, false)]);
    r.data.push(packet(far, const []));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(resyncs.single.facelets, far);
    expect(cube.currentState.facelets, far);
    await cube.disconnect();
  });

  test('battery is asked on the second service and read from byte 1', () async {
    final r = rig();
    final cube = await r.scanner.connect(await r.scanner.scan().first);

    final level = cube.batteryLevel();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(r.batteryWrite.written.single, const [GiikerDriver.reqBattery]);
    r.batteryRead.push(const [GiikerDriver.reqBattery, 88]);

    expect(await level, 88);
    await cube.disconnect();
  });

  test('a missing service fails the connect and hangs up the link', () async {
    final peripheral = _FakePeripheral('dev1', 'Gi-i3-ABC', []);
    final transport = _FakeTransport(
        peripheral, const BleScanResult(deviceId: 'dev1', name: 'Gi-i3-ABC'));
    final scanner = createCubeScanner(transport: transport);

    await expectLater(
        scanner.connect(await scanner.scan().first), throwsStateError);
    expect(peripheral.disconnected, isTrue);
  });
}

class _FakeChr implements BleCharacteristic {
  @override
  final String uuid;
  final _ctrl = StreamController<List<int>>.broadcast();
  final List<List<int>> written = [];
  List<int> readValue = const [];
  _FakeChr(this.uuid);
  void push(List<int> v) => _ctrl.add(v);
  @override
  Stream<List<int>> get onValue => _ctrl.stream;
  @override
  Future<void> enableNotifications() async {}
  @override
  Future<List<int>> read() async => readValue;
  @override
  Future<void> write(List<int> data, {bool withoutResponse = false}) async =>
      written.add(data);
}

class _FakeService implements BleService {
  @override
  final String uuid;
  @override
  final List<BleCharacteristic> characteristics;
  _FakeService(this.uuid, this.characteristics);
}

class _FakePeripheral implements BlePeripheral {
  @override
  final String id;
  @override
  final String name;
  final List<BleService> _services;
  final _conn = StreamController<bool>.broadcast();
  bool disconnected = false;
  _FakePeripheral(this.id, this.name, this._services);
  @override
  Stream<bool> get connected => _conn.stream;
  @override
  Future<List<BleService>> discoverServices() async => _services;
  @override
  Future<void> disconnect() async {
    disconnected = true;
    _conn.add(false);
  }
}

class _FakeTransport implements BleTransport {
  final BlePeripheral peripheral;
  final BleScanResult result;
  _FakeTransport(this.peripheral, this.result);
  @override
  Stream<BleScanResult> scan() => Stream.value(result);
  @override
  Future<void> stopScan() async {}
  @override
  Future<BlePeripheral> connect(String deviceId) async => peripheral;
}
