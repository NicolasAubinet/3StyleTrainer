/// Hardware validation tooling for the slice/wide reconstruction work (plan §31).
///
///  * **Sign triage** — confirms the §31a drift table against a real cube in a
///    couple of minutes. Deliberately uses NO timing assumptions: it waits for
///    an exact number of turns per step.
///  * **Trace capture** — records labelled move streams to JSONL for offline
///    timing analysis (`tool/trace_analyze.dart`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:smartcube/smartcube.dart';
// The sign triage validates the frame algebra itself, so it reaches past the
// package's public surface to the conventions under test.
// ignore: implementation_imports
import 'package:smartcube/src/reconstruct/frame_algebra.dart';

class TracePage extends StatefulWidget {
  final SmartCube cube;
  const TracePage(this.cube, {super.key});

  @override
  State<TracePage> createState() => _TracePageState();
}

class _TracePageState extends State<TracePage> {
  StreamSubscription<CubeMove>? _sub;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.cube.moves.listen(_onMove);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onMove(CubeMove m) {
    if (_tab == 0) {
      _triageMove(m);
    } else {
      _captureMove(m);
    }
  }

  // -------------------------------------------------------------------------
  // Sign triage
  // -------------------------------------------------------------------------

  /// Each step: do a slice on [axis], then turn the physical [probe] face CW.
  /// The probe face is chosen so it is NOT fixed under that axis's drift.
  static const _steps = [
    (axis: 'E', hint: 'middle horizontal layer, in the D direction', probe: Face.R),
    (axis: 'M', hint: 'middle vertical layer, in the L direction', probe: Face.U),
    (axis: 'S', hint: 'middle layer facing you, in the F direction', probe: Face.U),
  ];

  int _step = 0;
  int _phase = 0; // 0 = awaiting slice pair, 1 = awaiting probe turn
  FaceRotation _rho = kIdentity;
  final List<CubeMove> _pair = [];
  final List<String> _verdicts = [];
  String _live = '';

  void _resetTriage() => setState(() {
        _step = 0;
        _phase = 0;
        _rho = kIdentity;
        _pair.clear();
        _verdicts.clear();
        _live = '';
      });

  void _triageMove(CubeMove m) {
    if (_step >= _steps.length) return;
    final st = _steps[_step];

    if (_phase == 0) {
      _pair.add(m);
      setState(() => _live = 'sensed: ${_pair.map((e) => e.notation).join(" + ")}');
      if (_pair.length < 2) return;

      final f1 = toSolverFrame(_pair[0].face, _rho);
      final f2 = toSolverFrame(_pair[1].face, _rho);
      final d1 = _pair[0].prime ? 3 : 1;
      final d2 = _pair[1].prime ? 3 : 1;
      final hit = sliceForPair(f1, d1, f2, d2);
      final sensed = _pair.map((e) => e.notation).join(' + ');
      _pair.clear();

      if (hit == null) {
        setState(() {
          _verdicts.add('${st.axis}: ✗ sensed [$sensed] is not a slice pair '
              '(decodes to ${f1.name}/${f2.name}) — redo this step');
          _live = '';
        });
        return;
      }
      final dec = decomposeSlice(hit.slice, hit.amount);
      _rho = compose(dec.drift, _rho);
      setState(() {
        _live = 'read as ${hit.slice.name}${hit.amount == 3 ? "'" : ""} '
            '(sensed $sensed) — now turn the physical ${st.probe.name} face, clockwise';
        _phase = 1;
      });
      return;
    }

    // Phase 1: the probe. §31a predicts it decodes back to exactly what we asked
    // for; anything else means the drift table is wrong for this axis.
    final decoded = toSolverFrame(m.face, _rho);
    final ok = decoded == st.probe && !m.prime;
    setState(() {
      _verdicts.add('${st.axis}: ${ok ? "✓ PASS" : "✗ FAIL"} — asked for '
          '${st.probe.name}, cube reported ${m.notation}, decodes to '
          '${decoded.name}${m.prime ? "'" : ""}');
      _step++;
      _phase = 0;
      _live = '';
    });
  }

  Widget _triageView() {
    final done = _step >= _steps.length;
    final passed = _verdicts.where((v) => v.contains('PASS')).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('§31a sign triage',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Hold the cube in a fixed orientation for the whole test and do not '
          'rotate it. Each step: one slow slice, then one ordinary face turn.',
          style: TextStyle(fontSize: 12),
        ),
        const Divider(height: 24),
        if (!done) ...[
          Text('Step ${_step + 1} of ${_steps.length}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(_phase == 0
              ? 'Do one slow ${_steps[_step].axis} slice '
                  '(${_steps[_step].hint}). Either direction is fine.'
              : 'Now turn the physical ${_steps[_step].probe.name} face clockwise.'),
          if (_live.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_live, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ] else
          Text(
            passed == _steps.length
                ? '✓ ALL AXES PASS — the §31a drift table matches this cube.'
                : '✗ $passed/${_steps.length} axes pass — the table is wrong for '
                    'the failing axes. Record the actual output below in the plan.',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: passed == _steps.length ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
        const Divider(height: 24),
        for (final v in _verdicts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(v, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _resetTriage,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Restart triage'),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Trace capture
  // -------------------------------------------------------------------------

  final TextEditingController _label = TextEditingController();
  bool _recording = false;
  int _take = 0;
  final List<Map<String, Object?>> _rows = [];
  int _captured = 0;
  String _saveNote = '';

  String get _dir => '${Directory.current.path}${Platform.pathSeparator}cube_traces';

  void _captureMove(CubeMove m) {
    if (!_recording) return;
    _rows.add({
      'label': _label.text.trim(),
      // Each Record press is its own take, so repeating an alg produces
      // separate sequences instead of one merged (and meaningless) stream.
      'take': _take,
      'face': m.face.name,
      'prime': m.prime,
      'cubeMs': m.cubeTimestamp.inMilliseconds,
      'hostMs': m.hostTimestamp?.millisecondsSinceEpoch,
    });
    setState(() => _captured = _rows.length);
  }

  Future<void> _save() async {
    if (_rows.isEmpty) {
      setState(() => _saveNote = 'nothing captured');
      return;
    }
    final d = Directory(_dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    final name = 'trace_${DateTime.now().millisecondsSinceEpoch}.jsonl';
    final f = File('$_dir${Platform.pathSeparator}$name');
    f.writeAsStringSync(_rows.map(jsonEncode).join('\n'));
    setState(() => _saveNote = 'saved ${_rows.length} moves -> ${f.path}');
  }

  Widget _captureView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Trace capture',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Type the alg you are about to execute (solver notation, e.g. '
          '"M\' U R U\' M U R\' U\'"), press Record, execute it at your normal '
          'speed, then press Stop. Repeat for as many algs as you like, then Save.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _label,
          decoration: const InputDecoration(
            labelText: 'alg being executed (ground truth)',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => setState(() {
                if (!_recording) _take++;
                _recording = !_recording;
              }),
              icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
              label: Text(_recording ? 'Stop' : 'Record'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => setState(() {
                _rows.clear();
                _captured = 0;
                _saveNote = '';
              }),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('captured: $_captured moves', style: const TextStyle(fontFamily: 'monospace')),
        if (_saveNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_saveNote,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        const Divider(height: 24),
        const Text('last 20 moves', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final r in _rows.reversed.take(20))
          Text(
            '${r['face']}${(r['prime'] as bool) ? "'" : ""}  '
            'cube ${r['cubeMs']}ms  host ${r['hostMs'] ?? "-"}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('§31 validation')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Sign triage')),
                ButtonSegment(value: 1, label: Text('Trace capture')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          Expanded(child: _tab == 0 ? _triageView() : _captureView()),
        ],
      ),
    );
  }
}
