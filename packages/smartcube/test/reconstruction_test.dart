import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';

// 15ms apart: a real single motion. Wider spacing would split into separate
// motions and the direction tests below would pass without exercising anything.
List<CubeMove> turns(List<String> toks, {int spacing = 15}) {
  var t = 0;
  return [
    for (final tok in toks)
      CubeMove(
        face: Face.values.byName(tok.substring(0, 1)),
        prime: tok.endsWith("'"),
        cubeTimestamp: Duration(milliseconds: t += spacing),
      )
  ];
}

Reconstruction run(List<CubeMove> moves) => reconstruct(moves,
    startOrientation: kIdentity, timing: TimingQuality.perMoveClock);

void main() {
  group('a phantom half slice cannot be invented', () {
    // These four turns land in one motion and split 2/2 over opposite faces,
    // which used to be the whole test. But each face turns BOTH ways, so no
    // half turn happened. Reading it as a slice was wrong twice over: the
    // notation, and the drift it injects into every following move.
    test('mixed directions are not a half slice', () {
      // A quarter slice built from a valid sub-pair is still fair game here —
      // R R' L L legitimately reads as R M' L. What must not appear is a HALF
      // slice, which needs both turns on each face to go the same way.
      for (final c in [
        ['F', 'B', 'B', "F'"],
        ['R', "R'", 'L', 'L'],
        ['R', 'R', 'L', "L'"],
        ['R', "R'", 'L', "L'"],
      ]) {
        final halves = run(turns(c))
            .moves
            .where((m) => m.kind == MoveKind.slice && m.amount == 2);
        expect(halves, isEmpty, reason: c.join(' '));
      }
    });

    test('a real half slice is still recognised', () {
      expect(run(turns(['R', 'R', "L'", "L'"])).notation, 'M2');
      expect(run(turns(['U', 'U', "D'", "D'"])).notation, 'E2');
    });

    test('the phantom slice no longer misframes what follows', () {
      // F B B F' then a plain U. Under the old reading the F B B F' became S2,
      // whose z drift relabelled the U into something else entirely.
      final moves = turns(['F', 'B', 'B', "F'"])
        ..add(CubeMove(
            face: Face.U,
            prime: false,
            cubeTimestamp: const Duration(milliseconds: 400)));
      expect(run(moves).notation, endsWith('U'));
    });
  });

  group('motions too long to parse', () {
    test('are declined rather than reported with infinite confidence', () {
      // Six turns 10ms apart: one "motion" no hand could make. The old code
      // returned a single reading, so nothing differed from it and the margin
      // came back as infinity — maximum confidence for an unparseable group.
      final r = run(turns(['R', "L'", 'B', "F'", "L'", 'R'], spacing: 10));
      expect(r.abstained, isTrue);
      expect(r.margin, isNot(double.infinity));
      expect(r.note, isNotNull);
      expect(r.moves.every((m) => m.kind == MoveKind.outer), isTrue);
    });

    test('a fast run of ordinary turns does not chain into one motion', () {
      // Each gap is inside the 60ms window, but the run as a whole is far
      // longer than any single motion. Real captures do contain 50ms gaps.
      final six = turns(['R', 'U', 'F', 'L', 'D', 'B'], spacing: 50);
      expect(segmentMotions(six).length, greaterThan(1));
      expect(run(six).abstained, isFalse);
    });

    test('a genuine four-turn half slice still fits in one motion', () {
      expect(segmentMotions(turns(['R', 'R', "L'", "L'"], spacing: 15)).length, 1);
    });
  });

  group('timing quality', () {
    test('no clock declines and returns the raw reading', () {
      final moves = turns(["R'", 'L'], spacing: 10);
      final r = reconstruct(moves,
          startOrientation: kIdentity, timing: TimingQuality.none);
      expect(r.abstained, isTrue);
      expect(r.degraded, isTrue);
      expect(r.notation, "R' L");
    });

    test('a coarse clock answers but flags itself', () {
      final moves = turns(["R'", 'L'], spacing: 10);
      final r = reconstruct(moves,
          startOrientation: kIdentity, timing: TimingQuality.coarse);
      expect(r.degraded, isTrue);
    });
  });

  test('an empty stream is not an error', () {
    expect(run(const []).moves, isEmpty);
  });
}
