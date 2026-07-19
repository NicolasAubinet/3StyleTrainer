/// Verifies the §31a algebra end-to-end against a facelet simulator.
///
/// Claim: applying the solver-frame alg in the room frame gives the same cube
/// as applying the reported cube-frame stream and then rotating the whole cube
/// by the accumulated drift.

import 'dart:math';
import 'algebra.dart';
import 'cube.dart';
import 'corpus.dart';
import 'synth.dart';

void main() {
  final group = buildRotationGroup();
  print('rotation group size: ${group.length} (expect 24)');

  var ok = 0, fail = 0;
  final failures = <String>[];

  for (final algStr in allAlgs()) {
    final alg = parseAlg(algStr);
    for (var seed = 0; seed < 5; seed++) {
      final res = synthesize(alg, Random(seed));

      // Room frame: apply the solver alg directly.
      final roomState = applySolverAlg(CubeState.solved(), alg);

      // Cube frame: apply the reported stream as plain outer turns, then
      // rotate the whole cube by the accumulated drift.
      var cubeFrame = CubeState.solved();
      for (final r in res.stream) {
        cubeFrame = cubeFrame.turn(faceNormals[r.face], [1], r.prime ? 3 : 1);
      }
      final rotated = cubeFrame.applyOrientation(res.finalDrift);

      if (rotated == roomState) {
        ok++;
      } else {
        fail++;
        if (failures.length < 6) failures.add('$algStr (seed $seed)');
      }
    }
  }

  print('algebra check: $ok ok, $fail FAILED');
  for (final f in failures) {
    print('  FAIL: $f');
  }

  // Spot-check the headline maps from the plan.
  print('');
  print('spot checks (plan §31a):');
  _spot('E then R  -> expect U D\' then F', 'E R');
  _spot("M' then R -> expect R' L then R", "M' R");
  _spot('Rw        -> expect a bare L', 'Rw');
  _spot('x         -> expect nothing', 'x');
  _spot("U D' B U  -> owner's example", "U D' B U");
}

void _spot(String label, String algStr) {
  final res = synthesize(parseAlg(algStr), Random(1),
      const SynthConfig(pSimultaneousOuterPair: 0.0));
  final s = res.stream.map((r) => r.notation).join(' ');
  print('  $label\n     reported: [$s]  drift=${res.finalDrift}');
}
