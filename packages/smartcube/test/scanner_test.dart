import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:smartcube/src/drivers/moyu_v10_driver.dart';

// Same encrypted fixtures as moyu_v10_parser_test, for MAC CF:30:16:00:AB:CD.
// A cube named WCU_MY32_ABCD derives exactly that MAC, so the fixtures decode.
const c163 = [20, 81, 108, 156, 152, 10, 152, 58, 229, 121, 98, 221, 11, 123, 49, 53, 221, 107, 154, 186];
const c165 = [223, 209, 150, 204, 116, 21, 65, 40, 149, 201, 145, 0, 11, 185, 99, 221, 222, 17, 54, 129];
const uFacelet = 'UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB';

void main() {
  test('scan → connect → decode moves and states through a fake transport', () async {
    final r = _rig();

    final discovered = await r.scanner.scan().first;
    expect(discovered.brand, CubeBrand.moyuV10);
    expect(discovered.needsMac, isFalse); // MAC derived from the name

    // Connect only completes once the cube answers with a state it can decode,
    // so the answer has to come while the handshake is still in flight.
    final connecting = r.scanner.connect(discovered);
    while (r.writeChr.written.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    r.readChr.push(c163); // solved anchor
    final cube = await connecting;

    expect(cube.connection, CubeConnection.ready);
    // Handshake requests were written (info, status, power).
    expect(r.writeChr.written.length, 3);
    // Ready means anchored: the state is the cube's own, not an assumption.
    expect(cube.currentState.facelets, CubieCube.solvedFacelet);

    final states = <CubeState>[];
    final moves = <CubeMove>[];
    cube.states.listen(states.add);
    cube.moves.listen(moves.add);

    r.readChr.push(c165); // one U move
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(moves.single.face, Face.U);
    expect(moves.single.prime, isFalse);
    expect(states.last.facelets, uFacelet);
    expect(cube.currentState.facelets, uFacelet);
  });

  test('a wrong MAC is reported, not handed back as a mute cube', () async {
    final r = _rig();
    // CF:30:16:02 is the V11 OUI, and the name derives the V10 one — exactly
    // what a name-derived guess gets wrong on web, where it is the only clue.
    const wrongMac = 'CF:30:16:02:52:88';
    final driver = MoyuV10Driver(
        macProbeTimeout: const Duration(milliseconds: 300));
    final adv = CubeAdvertisement(id: 'dev1', name: 'WCU_MY32_ABCD');

    // The cube does answer; under the wrong key it just decodes to noise.
    Timer.run(() => r.readChr.push(c163));

    await expectLater(
      driver.connect(r.peripheral, adv, macAddress: wrongMac),
      throwsA(isA<CubeMacRejectedException>()
          .having((e) => e.attemptedMac, 'attemptedMac', wrongMac)),
    );
    // It kept asking rather than giving up on the first unanswered request.
    expect(r.writeChr.written.length, greaterThan(2));
    // The link must not be left half-open for a retry to stack onto.
    expect(r.peripheral.disconnected, isTrue);
  });
}

_Rig _rig() {
  final readChr = _FakeChr(normalizeUuid(MoyuV10Driver.readChrUuid));
  final writeChr = _FakeChr(normalizeUuid(MoyuV10Driver.writeChrUuid));
  final service = _FakeService(
      normalizeUuid(MoyuV10Driver.serviceUuid), [readChr, writeChr]);
  final peripheral = _FakePeripheral('dev1', 'WCU_MY32_ABCD', [service]);
  return _Rig(
    scanner: createCubeScanner(
      transport: _FakeTransport(
        peripheral,
        BleScanResult(
          deviceId: 'dev1',
          name: 'WCU_MY32_ABCD',
          serviceUuids: [normalizeUuid(MoyuV10Driver.serviceUuid)],
        ),
      ),
    ),
    peripheral: peripheral,
    readChr: readChr,
    writeChr: writeChr,
  );
}

class _Rig {
  final CubeScanner scanner;
  final _FakePeripheral peripheral;
  final _FakeChr readChr;
  final _FakeChr writeChr;
  _Rig({
    required this.scanner,
    required this.peripheral,
    required this.readChr,
    required this.writeChr,
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
  Future<List<int>> read() async => const [];
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
