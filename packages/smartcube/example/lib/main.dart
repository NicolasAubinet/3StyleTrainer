import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smartcube/smartcube.dart';

import 'trace_page.dart';

void main() => runApp(const SmartCubeExampleApp());

class SmartCubeExampleApp extends StatelessWidget {
  const SmartCubeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'smartcube example',
      theme: ThemeData.dark(useMaterial3: true),
      home: const CubePage(),
    );
  }
}

class CubePage extends StatefulWidget {
  const CubePage({super.key});

  @override
  State<CubePage> createState() => _CubePageState();
}

class _CubePageState extends State<CubePage> {
  final CubeScanner _scanner = createCubeScanner();
  StreamSubscription<DiscoveredCube>? _scanSub;
  final Map<String, DiscoveredCube> _found = {};

  SmartCube? _cube;
  CubeConnection _connection = CubeConnection.disconnected;
  CubeState _state = CubeState.solved;
  int? _battery;
  final List<String> _log = [];

  void _addLog(String s) => setState(() {
        _log.insert(0, s);
        if (_log.length > 200) _log.removeLast();
      });

  Future<void> _startScan() async {
    setState(_found.clear);
    await _scanSub?.cancel();
    _scanSub = _scanner.scan().listen((cube) {
      setState(() => _found[cube.id] = cube);
    }, onError: (Object e) => _addLog('scan error: $e'));
  }

  Future<void> _connect(DiscoveredCube d) async {
    await _scanner.stopScan();
    await _scanSub?.cancel();
    _addLog('connecting to ${d.name}…');
    try {
      final cube = await _scanner.connect(d);
      _cube = cube;
      cube.connectionEvents.listen((c) => setState(() => _connection = c));
      cube.states.listen((s) => setState(() => _state = s));
      cube.moves.listen((m) => _addLog(
          'move ${m.notation}   @ ${m.cubeTimestamp.inMilliseconds} ms'));
      final batt = await cube.batteryLevel();
      setState(() {
        _connection = cube.connection;
        _battery = batt;
      });
      _addLog('connected · battery ${batt ?? "?"}%');
    } catch (e) {
      _addLog('connect failed: $e');
    }
  }

  Future<void> _disconnect() async {
    await _cube?.disconnect();
    setState(() {
      _cube = null;
      _connection = CubeConnection.disconnected;
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _cube?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _cube != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('smartcube'),
        actions: [
          if (connected)
            IconButton(
              tooltip: '§31 validation (sign triage / trace capture)',
              icon: const Icon(Icons.science_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TracePage(_cube!),
              )),
            ),
          if (connected)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                  child: Text('${_battery ?? "?"}%  ·  ${_connection.name}')),
            ),
        ],
      ),
      floatingActionButton: connected
          ? FloatingActionButton.extended(
              onPressed: _disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
              label: const Text('Disconnect'),
            )
          : FloatingActionButton.extended(
              onPressed: _startScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Scan'),
            ),
      body: connected ? _connectedView() : _scanView(),
    );
  }

  Widget _scanView() {
    if (_found.isEmpty) {
      return const Center(child: Text('Tap Scan, then power on your cube.'));
    }
    return ListView(
      children: [
        for (final d in _found.values)
          ListTile(
            leading: const Icon(Icons.view_in_ar),
            title: Text(d.name.isEmpty ? '(unnamed)' : d.name),
            subtitle: Text('${d.brand.name}${d.needsMac ? " · MAC needed" : ""}'),
            onTap: () => _connect(d),
          ),
      ],
    );
  }

  Widget _connectedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('solved: ${_state.isSolved ? "YES" : "no"}',
                      style: TextStyle(
                          color: _state.isSolved
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () async {
                      await _cube?.syncState(CubeState.solved);
                      setState(() => _state = CubeState.solved);
                      _addLog('state synced to solved');
                    },
                    child: const Text('I solved it'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _FaceletView(_state.facelets),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _log.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_log[i],
                  style: const TextStyle(fontFamily: 'monospace')),
            ),
          ),
        ),
      ],
    );
  }
}

/// Minimal unfolded-net view of a 54-char URFDLB facelet string.
class _FaceletView extends StatelessWidget {
  final String facelets;
  const _FaceletView(this.facelets);

  static const _colors = {
    'U': Colors.white,
    'R': Colors.red,
    'F': Colors.green,
    'D': Colors.yellow,
    'L': Colors.orange,
    'B': Colors.blue,
  };

  List<int> _face(int f) => List.generate(9, (i) => f * 9 + i);

  Widget _grid(List<int> idx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < 3; r++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var c = 0; c < 3; c++)
                  Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.all(1),
                    color: _colors[facelets[idx[r * 3 + c]]] ?? Colors.grey,
                  ),
              ],
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (facelets.length != 54) return const SizedBox.shrink();
    const gap = SizedBox(width: 6);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grid(_face(4)), // L
          gap,
          _grid(_face(2)), // F
          gap,
          _grid(_face(1)), // R
          gap,
          _grid(_face(5)), // B
          gap,
          _grid(_face(0)), // U
          gap,
          _grid(_face(3)), // D
        ],
      ),
    );
  }
}
