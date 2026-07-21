import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:smartcube/smartcube.dart' as sc;

/// Appends every finished case's raw quarter-turn stream to a JSONL file under
/// `cube_traces/`, one file per app session, in the same row format as the
/// example app's trace capture — so a strange live reconstruction can be
/// replayed and diagnosed offline instead of reconstructed from memory.
///
/// Desktop only (`dart:io`); a failure to write must never disturb a solve.
class SolveTrace {
  static final SolveTrace _instance = SolveTrace._();
  factory SolveTrace() => _instance;
  SolveTrace._();

  IOSink? _sink;
  int _take = 0;
  bool _disabled = false;

  void log(
    String label,
    List<sc.CubeMove> moves, {
    required String top,
    required String front,
    String? result,
  }) {
    if (kIsWeb || _disabled || moves.isEmpty) return;
    // On mobile the working directory is not writable; don't keep retrying.
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      _disabled = true;
      return;
    }
    _take++;
    try {
      final sink = _sink ??= _open();
      for (final m in moves) {
        sink.writeln(jsonEncode({
          'label': label,
          'take': _take,
          'face': m.face.name,
          'prime': m.prime,
          'cubeMs': m.cubeTimestamp.inMilliseconds,
          'hostMs': m.hostTimestamp?.millisecondsSinceEpoch,
          'top': top,
          'front': front,
          if (result != null) 'result': result,
        }));
      }
      sink.flush();
    } catch (_) {
      // Tracing is best-effort by design; a failing filesystem stays failed.
      _disabled = true;
    }
  }

  IOSink _open() {
    final dir = Directory(
        '${Directory.current.path}${Platform.pathSeparator}cube_traces');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}'
        'solves_${DateTime.now().millisecondsSinceEpoch}.jsonl');
    return f.openWrite(mode: FileMode.append);
  }
}
