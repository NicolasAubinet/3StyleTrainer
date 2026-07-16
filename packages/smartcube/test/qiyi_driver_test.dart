import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:smartcube/src/crypto/aes128.dart';
import 'package:smartcube/src/drivers/qiyi_driver.dart';
import 'package:smartcube/src/drivers/qiyi_parser.dart';

/// End-to-end through a fake transport: scan → connect → handshake → decode.
void main() {
  final aes = Aes128(QiyiParser.fixedKey);

  List<int> mapBlocks(List<int> data, List<int> Function(List<int>) f) {
    final out = List<int>.of(data);
    for (var off = 0; off + 16 <= out.length; off += 16) {
      out.setRange(off, off + 16, f(out.sublist(off, off + 16)));
    }
    return out;
  }

  List<int> frame(List<int> content) {
    final msg = <int>[0xFE, content.length + 4, ...content];
    final crc = QiyiParser.crc16Modbus(msg);
    msg
      ..add(crc & 0xFF)
      ..add(crc >> 8);
    while (msg.length % 16 != 0) {
      msg.add(0);
    }
    return mapBlocks(msg, aes.encrypt);
  }

  List<int> stateBytes(String facelets) {
    const colour = {'L': 0, 'R': 1, 'D': 2, 'U': 3, 'F': 4, 'B': 5};
    return [
      for (var i = 0; i < 27; i++)
        colour[facelets[i * 2]]! | (colour[facelets[i * 2 + 1]]! << 4),
    ];
  }

  List<int> cubeHello(String facelets) => frame([
        QiyiParser.opCubeHello,
        0, 0, 0x03, 0xE8, //
        ...stateBytes(facelets),
        0,
        88,
      ]);

  List<int> stateChange(String facelets, {int move = 0, bool needsAck = false}) =>
      frame([
        QiyiParser.opStateChange,
        0, 0, 0x07, 0xD0, //
        ...stateBytes(facelets),
        move,
        88,
        ...List<int>.filled(55, 0),
        needsAck ? 1 : 0,
      ]);

  const uFacelets = 'UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB';

  ({_FakeChr chr, CubeScanner scanner}) rig({String name = 'QY-QYSC-1-ABCD'}) {
    final chr = _FakeChr(normalizeUuid(QiyiDriver.chrUuid));
    final service = _FakeService(normalizeUuid(QiyiDriver.serviceUuid), [chr]);
    final peripheral = _FakePeripheral('dev1', name, [service]);
    final transport = _FakeTransport(
      peripheral,
      BleScanResult(
        deviceId: 'dev1',
        name: name,
        serviceUuids: [normalizeUuid(QiyiDriver.serviceUuid)],
      ),
    );
    return (chr: chr, scanner: createCubeScanner(transport: transport));
  }

  test('scan → connect → hello → decode moves and states', () async {
    final r = rig();

    final discovered = await r.scanner.scan().first;
    expect(discovered.brand, CubeBrand.qiyi);
    expect(discovered.needsMac, isFalse); // MAC derived from the name

    final cube = await r.scanner.connect(discovered);
    expect(cube.connection, CubeConnection.ready);

    // The app must greet the cube first, or it never says anything.
    expect(r.chr.written, hasLength(1));
    final hello = mapBlocks(r.chr.written.single, aes.decrypt);
    expect(hello.sublist(13, 19), [0xCD, 0xAB, 0x00, 0x00, 0xA3, 0xCC]);

    final states = <CubeState>[];
    final moves = <CubeMove>[];
    cube.states.listen(states.add);
    cube.moves.listen(moves.add);

    r.chr.push(cubeHello(CubeState.solvedFacelets));
    r.chr.push(stateChange(uFacelets, move: 8));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(states.first, CubeState.solved);
    expect(moves.single.face, Face.U);
    expect(moves.single.prime, isFalse);
    expect(states.last.facelets, uFacelets);
    expect(cube.currentState.facelets, uFacelets);
    expect(await cube.batteryLevel(), 88);

    // The cube hello is acked, and the app stops repeating its own hello.
    expect(r.chr.written, hasLength(2));
    await cube.disconnect();
  });

  test('the app keeps saying hello until the cube answers', () async {
    fakeAsync((async) {
      final r = rig();
      CubeState? first;
      r.scanner.scan().first.then((d) => r.scanner.connect(d)).then((cube) {
        cube.states.listen((s) => first ??= s);
      });
      async.flushMicrotasks();
      expect(r.chr.written, hasLength(1));

      // No answer: a lost hello write would otherwise be a dead connection.
      async.elapse(const Duration(seconds: 3));
      expect(r.chr.written.length, greaterThan(2));

      final beforeAnswer = r.chr.written.length;
      r.chr.push(cubeHello(CubeState.solvedFacelets));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));

      expect(first, CubeState.solved);
      // Only the ack — the hello loop stopped once the cube spoke.
      expect(r.chr.written.length, beforeAnswer + 1);
    });
  });

  test('a state change needing an ack is acked and read as solved', () async {
    final r = rig();
    final cube = await r.scanner.connect(await r.scanner.scan().first);
    final states = <CubeState>[];
    cube.states.listen(states.add);

    r.chr.push(cubeHello(uFacelets));
    r.chr.push(stateChange(uFacelets, move: 8, needsAck: true));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(states.last, CubeState.solved);
    expect(r.chr.written, hasLength(3)); // hello + 2 acks
    await cube.disconnect();
  });

  test('a missing service fails the connect and hangs up the link', () async {
    final peripheral = _FakePeripheral('dev1', 'QY-QYSC-1-ABCD', []);
    final transport = _FakeTransport(peripheral,
        const BleScanResult(deviceId: 'dev1', name: 'QY-QYSC-1-ABCD'));
    final scanner = createCubeScanner(transport: transport);
    final discovered = await scanner.scan().first;

    await expectLater(scanner.connect(discovered), throwsStateError);
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
