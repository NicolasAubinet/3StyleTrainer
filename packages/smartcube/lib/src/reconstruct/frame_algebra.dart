/// Frame algebra for slice / wide-move reconstruction (plan §31a).
///
/// A smart cube reports face turns in its own **core-relative frame**. A slice
/// or wide move rotates the core, so every move after it is reported on a
/// rotated frame. This file is the pure algebra of that drift; it holds no
/// heuristics and makes no guesses.
///
/// The central identity:
///
///   **reported -> solver = rho**, where `rho` is the core's rotation in space.
///
/// Verified end-to-end against an independent facelet simulator
/// (`tool/slice_eval/verify.dart`): 250/250.
///
/// > Both columns are HARDWARE-CONFIRMED: the sensed pairs in §25, and the
/// > drifts by the §31g sign triage on a MoYu V10 (2026-07-19, all axes pass).
/// > Re-run that triage when a new brand's driver lands.
library;

import '../model/cube_move.dart';

/// A rotation of the cube, as a permutation of the six faces: `perm[f]` is the
/// position face `f` moves to.
///
/// Named FaceRotation, not CubeOrientation, because the trainer app already has
/// a CubeOrientation class and the two would collide at every call site.
typedef FaceRotation = List<int>;

const FaceRotation kIdentity = [0, 1, 2, 3, 4, 5];

/// x follows R: F->U, U->B, B->D, D->F; R,L fixed.
const FaceRotation kRotX = [5, 4, 2, 3, 0, 1];

/// y follows U: F->L, L->B, B->R, R->F; U,D fixed.
const FaceRotation kRotY = [0, 1, 5, 4, 2, 3];

/// z follows F: U->R, R->D, D->L, L->U; F,B fixed.
const FaceRotation kRotZ = [3, 2, 0, 1, 4, 5];

/// `(a . b)[f] = a[b[f]]`
FaceRotation compose(FaceRotation a, FaceRotation b) =>
    List<int>.generate(6, (f) => a[b[f]]);

FaceRotation invert(FaceRotation p) {
  final inv = List<int>.filled(6, 0);
  for (var f = 0; f < 6; f++) {
    inv[p[f]] = f;
  }
  return inv;
}

FaceRotation power(FaceRotation p, int n) {
  var acc = kIdentity;
  for (var i = 0; i < n; i++) {
    acc = compose(p, acc);
  }
  return acc;
}

String orientationKey(FaceRotation p) => p.join(',');

bool isIdentity(FaceRotation p) => orientationKey(p) == orientationKey(kIdentity);

/// The 24 orientations of a cube.
List<FaceRotation> rotationGroup() {
  final seen = <String, FaceRotation>{orientationKey(kIdentity): kIdentity};
  final queue = <FaceRotation>[kIdentity];
  while (queue.isNotEmpty) {
    final cur = queue.removeLast();
    for (final g in [kRotX, kRotY, kRotZ]) {
      final next = compose(g, cur);
      if (seen.putIfAbsent(orientationKey(next), () => next) == next) {
        queue.add(next);
      }
    }
  }
  return seen.values.toList();
}

const Map<Face, Face> kOpposite = {
  Face.U: Face.D,
  Face.D: Face.U,
  Face.L: Face.R,
  Face.R: Face.L,
  Face.F: Face.B,
  Face.B: Face.F,
};

/// The three middle layers. `M` follows `L`, `E` follows `D`, `S` follows `F`.
enum Slice { M, E, S }

/// One sensed outer turn: a face and a quarter-turn count (1 = CW, 2, 3 = CCW).
class SensedTurn {
  final Face face;
  final int amount;
  const SensedTurn(this.face, this.amount);
  @override
  String toString() =>
      '${face.name}${amount == 1 ? "" : (amount == 2 ? "2" : "'")}';
}

/// What the cube senses for a move (in the frame the move is named in), and the
/// core rotation the move imparts.
class Decomposition {
  final List<SensedTurn> sensed;
  final FaceRotation drift;
  const Decomposition(this.sensed, this.drift);
}

int inverseAmount(int a) => a == 2 ? 2 : (a == 1 ? 3 : 1);

/// Sensed pair + drift for a slice (§31a).
///
///   M  = R  + L' , rho = x'     E  = U  + D' , rho = y'     S  = F' + B , rho = z
Decomposition decomposeSlice(Slice slice, int amount) {
  late Face a, b;
  late int da, db;
  late FaceRotation axis;
  switch (slice) {
    case Slice.M:
      a = Face.R;
      b = Face.L;
      da = 1;
      db = 3;
      axis = invert(kRotX);
    case Slice.E:
      a = Face.U;
      b = Face.D;
      da = 1;
      db = 3;
      axis = invert(kRotY);
    case Slice.S:
      a = Face.F;
      b = Face.B;
      da = 3;
      db = 1;
      axis = kRotZ;
  }
  if (amount == 2) {
    return Decomposition(
        [SensedTurn(a, 2), SensedTurn(b, 2)], power(axis, 2));
  }
  if (amount == 3) {
    return Decomposition(
      [SensedTurn(a, inverseAmount(da)), SensedTurn(b, inverseAmount(db))],
      invert(axis),
    );
  }
  return Decomposition([SensedTurn(a, da), SensedTurn(b, db)], axis);
}

/// A wide move senses as a **single** turn on the OPPOSITE face, same amount,
/// and carries the drift of the slice inside it.
///
///   Rw = R M' -> sensed L, rho = x      Uw -> sensed D, rho = y
Decomposition decomposeWide(Face face, int amount) {
  final base = switch (face) {
    Face.R => kRotX,
    Face.L => invert(kRotX),
    Face.U => kRotY,
    Face.D => invert(kRotY),
    Face.F => kRotZ,
    Face.B => invert(kRotZ),
  };
  final drift =
      amount == 2 ? power(base, 2) : (amount == 3 ? invert(base) : base);
  return Decomposition([SensedTurn(kOpposite[face]!, amount)], drift);
}

/// Whole-cube rotations sense as **nothing at all**.
///
/// No caller in the parser — [MoveKind] has no rotation, so one can never be
/// emitted. Kept because this file is the written algebra a port follows, and
/// "a rotation is invisible to the cube" is part of it.
Decomposition decomposeRotation(int axis, int amount) {
  final base = [kRotX, kRotY, kRotZ][axis];
  return Decomposition(
      const [], amount == 2 ? power(base, 2) : (amount == 3 ? invert(base) : base));
}

/// Given a sensed pair in the solver frame, the slice it forms — or null.
({Slice slice, int amount})? sliceForPair(
    Face f1, int d1, Face f2, int d2) {
  for (final s in Slice.values) {
    for (final amt in [1, 3]) {
      final dec = decomposeSlice(s, amt);
      final a = dec.sensed[0], b = dec.sensed[1];
      if ((a.face == f1 && a.amount == d1 && b.face == f2 && b.amount == d2) ||
          (a.face == f2 && a.amount == d2 && b.face == f1 && b.amount == d1)) {
        return (slice: s, amount: amt);
      }
    }
  }
  return null;
}

/// One sensed turn as it arrived: a face and a direction.
typedef SensedQuarter = ({Face face, bool prime});

/// The half slice four sensed quarter turns form, or null.
///
/// Lives here rather than in the parser so the direction check cannot be
/// forgotten: both turns on each face must go the SAME way, because that is
/// what makes each pair a half turn. Without it `F B B F'` reads as `S2` — not
/// merely wrong notation, but a phantom drift that relabels every move after
/// it.
Slice? halfSliceForTurns(List<SensedQuarter> turns) {
  if (turns.length != 4) return null;
  final byFace = <Face, List<bool>>{};
  for (final t in turns) {
    byFace.putIfAbsent(t.face, () => []).add(t.prime);
  }
  if (byFace.length != 2) return null;
  final faces = byFace.keys.toList();
  if (kOpposite[faces[0]] != faces[1]) return null;
  for (final dirs in byFace.values) {
    if (dirs.length != 2 || dirs[0] != dirs[1]) return null;
  }
  for (final s in Slice.values) {
    final sensed = decomposeSlice(s, 2).sensed;
    if ((sensed[0].face == faces[0] && sensed[1].face == faces[1]) ||
        (sensed[0].face == faces[1] && sensed[1].face == faces[0])) {
      return s;
    }
  }
  return null;
}

/// Map a reported face into the solver frame under drift [rho].
Face toSolverFrame(Face reported, FaceRotation rho) =>
    Face.values[rho[reported.index]];

/// Map a solver-frame face into what the cube would report under drift [rho].
Face toReportedFrame(Face solver, FaceRotation rho) =>
    Face.values[invert(rho)[solver.index]];
