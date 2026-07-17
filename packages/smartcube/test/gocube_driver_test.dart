import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:smartcube/src/drivers/gocube_driver.dart';
import 'package:smartcube/src/drivers/gocube_parser.dart';

/// End-to-end through a fake transport: scan → connect → decode. GoCube needs no
/// MAC and no crypto, so there is nothing to hand-derive — the cube just streams.
void main() {
  const axisPerm = [5, 2, 0, 3, 1, 4];
  const facePerm = [0, 1, 2, 5, 8, 7, 6, 3];
  const faceOffset = [0, 0, 6, 2, 0, 0];
  const colours = 'BFUDRL';
  const uFacelet = 'UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB';

  List<int> frame(int type, List<int> data) =>
      [0x2a, data.length, type, ...data, 0x00, 0x0d, 0x0a];

  List<int> stateData(String facelet) {
    final data = List<int>.filled(54, 0);
    for (var a = 0; a < 6; a++) {
      final base = axisPerm[a] * 9;
      final aoff = faceOffset[a];
      data[a * 9] = colours.indexOf(facelet[base + 4]);
      for (var i = 0; i < 8; i++) {
        data[a * 9 + i + 1] =
            colours.indexOf(facelet[base + facePerm[(i + aoff) % 8]]);
      }
    }
    return data;
  }

  List<int> statePacket(String f) => frame(GoCubeParser.msgState, stateData(f));

  ({_FakeChr read, _FakeChr write, CubeScanner scanner}) rig(
      {String name = 'GoCube_ABC'}) {
    final read = _FakeChr(normalizeUuid(GoCubeDriver.readChrUuid));
    final write = _FakeChr(normalizeUuid(GoCubeDriver.writeChrUuid));
    final service =
        _FakeService(normalizeUuid(GoCubeDriver.serviceUuid), [read, write]);
    final peripheral = _FakePeripheral('dev1', name, [service]);
    final transport = _FakeTransport(
      peripheral,
      BleScanResult(
        deviceId: 'dev1',
        name: name,
        serviceUuids: [normalizeUuid(GoCubeDriver.serviceUuid)],
      ),
    );
    return (read: read, write: write, scanner: createCubeScanner(transport: transport));
  }

  test('scan discovers a GoCube needing no MAC', () async {
    final discovered = await rig().scanner.scan().first;
    expect(discovered.brand, CubeBrand.gocube);
    expect(discovered.needsMac, isFalse);
  });

  test("a Rubik's Connected name is discovered too", () async {
    final discovered = await rig(name: 'Rubiks_XY').scanner.scan().first;
    expect(discovered.brand, CubeBrand.gocube);
  });

  test('connect → anchor → decode moves and states', () async {
    final r = rig();
    final cube = await r.scanner.connect(await r.scanner.scan().first);
    expect(cube.connection, CubeConnection.ready);

    final states = <CubeState>[];
    final moves = <CubeMove>[];
    cube.states.listen(states.add);
    cube.moves.listen(moves.add);

    r.read.push(statePacket(CubieCube.solvedFacelet)); // anchor
    r.read.push(frame(GoCubeParser.msgMove, [4, 0])); // U
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(states.first, CubeState.solved);
    expect(moves.single.face, Face.U);
    expect(moves.single.prime, isFalse);
    expect(states.last.facelets, uFacelet);
    expect(cube.currentState.facelets, uFacelet);
    await cube.disconnect();
  });

  test('the app keeps requesting state until the cube anchors', () async {
    final r = rig();
    final cube = await r.scanner.connect(await r.scanner.scan().first);

    // A battery request plus the first state request on connect.
    expect(r.write.written.any((w) => w.contains(GoCubeParser.reqState)), isTrue);
    final before = r.write.written.length;

    // No state answer yet: the request repeats rather than giving up.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(r.write.written.length, greaterThan(before));

    r.read.push(statePacket(CubieCube.solvedFacelet));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final afterAnchor = r.write.written.length;

    // Once anchored the retry loop stops.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(r.write.written.length, afterAnchor);
    await cube.disconnect();
  });

  test('a state disagreeing with tracked moves fires a resync', () async {
    final r = rig();
    final cube = await r.scanner.connect(await r.scanner.scan().first);
    final resyncs = <CubeState>[];
    cube.resyncs.listen(resyncs.add);

    r.read.push(statePacket(CubieCube.solvedFacelet)); // anchor solved
    r.read.push(statePacket(uFacelet)); // cube is actually U — moves were lost
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(resyncs.single.facelets, uFacelet);
    await cube.disconnect();
  });

  test('a missing service fails the connect and hangs up the link', () async {
    final peripheral = _FakePeripheral('dev1', 'GoCube_ABC', []);
    final transport = _FakeTransport(
        peripheral, const BleScanResult(deviceId: 'dev1', name: 'GoCube_ABC'));
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
  _FakeChr(this.uuid);
  void push(List<int> v) => _ctrl.add(v);
  @override
  Stream<List<int>> get onValue => _ctrl.stream;
  @override
  Future<void> enableNotifications() async {}
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
