import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';

List<String> _drain(AlgProvider p) {
  final out = <String>[];
  for (Alg? a = p.getNextAlg(); a != null; a = p.getNextAlg()) {
    out.add(a.name);
  }
  return out;
}

void main() {
  test('requeue puts a served alg back into the pool', () {
    final p = CornersAlgProvider(setIndices: [0]);
    final total = p.totalAlgs;
    final first = p.getNextAlg()!; // removed from the pool

    p.requeue(first.name);

    final remaining = _drain(p);
    expect(remaining, contains(first.name),
        reason: 'requeued case must reappear in the same run');
    expect(remaining.length, total, reason: 'pool size restored by requeue');
  });

  test('requeue is idempotent for a case already in the pool', () {
    final p = CornersAlgProvider(setIndices: [0]);
    final a = p.getNextAlg()!;
    p.requeue(a.name);
    p.requeue(a.name); // no-op second time

    final remaining = _drain(p);
    expect(remaining.where((n) => n == a.name).length, 1);
  });

  test('requeue lifts the progression denominator back up', () {
    final p = CornersAlgProvider(setIndices: [0]);
    p.getNextAlg();
    final afterOne = p.getProgression();
    final served = p.getNextAlg()!;
    final afterTwo = p.getProgression();
    p.requeue(served.name);
    // Putting it back returns progression toward the two-served level's inverse.
    expect(p.getProgression(), lessThan(afterTwo));
    expect(p.getProgression(), afterOne);
  });
}
