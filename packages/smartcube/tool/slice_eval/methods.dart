/// Method A — the local rule as originally proposed.
/// Method B — beam search over the 24-orientation frame group with structural
///            scoring (plan §31b/c).

import 'algebra.dart';
import 'synth.dart';

const int kSliceWindowMs = 55;
const int kHalfWindowMs = 60;

/// Sensed patterns, in the SOLVER frame: sliceId, amount -> (faceA,dirA,faceB,dirB)
class _SlicePattern {
  final int sliceId, amount, faceA, dirA, faceB, dirB;
  const _SlicePattern(
      this.sliceId, this.amount, this.faceA, this.dirA, this.faceB, this.dirB);
}

final List<_SlicePattern> slicePatterns = () {
  final out = <_SlicePattern>[];
  for (var id = 0; id < 3; id++) {
    for (final amt in [1, 3]) {
      final dec = decomposeSlice(id, amt);
      out.add(_SlicePattern(id, amt, dec.sensed[0].face, dec.sensed[0].amount,
          dec.sensed[1].face, dec.sensed[1].amount));
    }
  }
  return out;
}();

/// Does the solver-frame pair (f1,d1),(f2,d2) form a slice? Returns the slice
/// move, or null.
Move? matchSlice(int f1, int d1, int f2, int d2) {
  for (final p in slicePatterns) {
    if (p.faceA == f1 && p.dirA == d1 && p.faceB == f2 && p.dirB == d2) {
      return Move(MoveKind.slice, p.sliceId, p.amount);
    }
    if (p.faceA == f2 && p.dirA == d2 && p.faceB == f1 && p.dirB == d1) {
      return Move(MoveKind.slice, p.sliceId, p.amount);
    }
  }
  return null;
}

/// The half slice four solver-frame quarter turns form, or null.
///
/// Takes directions, not just faces: both turns on each face must go the SAME
/// way, or `F B B F'` reads as `S2` — a phantom drift that relabels every move
/// after it. Mirrors halfSliceForTurns in the shipped parser.
Move? matchSliceHalf(List<({int face, bool prime})> turns) {
  if (turns.length != 4) return null;
  final byFace = <int, List<bool>>{};
  for (final t in turns) {
    byFace.putIfAbsent(t.face, () => []).add(t.prime);
  }
  if (byFace.length != 2) return null;
  final faces = byFace.keys.toList();
  if (oppositeFace[faces[0]] != faces[1]) return null;
  for (final dirs in byFace.values) {
    if (dirs.length != 2 || dirs[0] != dirs[1]) return null;
  }
  for (var id = 0; id < 3; id++) {
    final dec = decomposeSlice(id, 2);
    final a = dec.sensed[0].face, b = dec.sensed[1].face;
    if ((a == faces[0] && b == faces[1]) || (a == faces[1] && b == faces[0])) {
      return Move(MoveKind.slice, id, 2);
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Method A: local greedy rule
// ---------------------------------------------------------------------------

class MethodAConfig {
  /// Reject a slice when the following solver-frame move lands on F or B.
  final bool useFollowingMoveTest;
  const MethodAConfig({this.useFollowingMoveTest = true});
}

List<Move> methodA(List<Reported> obs, [MethodAConfig cfg = const MethodAConfig()]) {
  var rho = identity;
  final out = <Move>[];
  var i = 0;
  while (i < obs.length) {
    final a = obs[i];
    final b = i + 1 < obs.length ? obs[i + 1] : null;

    // 4-cluster half slice?
    if (i + 3 < obs.length && obs[i + 3].tMs - a.tMs <= kSliceWindowMs) {
      final m = matchSliceHalf([
        for (var k = i; k < i + 4; k++)
          (face: rho[obs[k].face], prime: obs[k].prime)
      ]);
      if (m != null) {
        final drift = decompose(m).drift;
        if (_acceptA(cfg, obs, i + 4, compose(drift, rho))) {
          out.add(m);
          rho = compose(drift, rho);
          i += 4;
          continue;
        }
      }
    }

    if (b != null && b.tMs - a.tMs <= kSliceWindowMs) {
      final f1 = rho[a.face], f2 = rho[b.face];
      if (oppositeFace[f1] == f2) {
        final m = matchSlice(f1, a.prime ? 3 : 1, f2, b.prime ? 3 : 1);
        if (m != null) {
          final drift = decompose(m).drift;
          if (_acceptA(cfg, obs, i + 2, compose(drift, rho))) {
            out.add(m);
            rho = compose(drift, rho);
            i += 2;
            continue;
          }
        }
      }
    }

    // Outer half turn?
    if (b != null &&
        b.face == a.face &&
        b.prime == a.prime &&
        b.tMs - a.tMs <= kHalfWindowMs) {
      out.add(Move(MoveKind.outer, rho[a.face], 2));
      i += 2;
      continue;
    }

    out.add(Move(MoveKind.outer, rho[a.face], a.prime ? 3 : 1));
    i += 1;
  }
  return out;
}

bool _acceptA(MethodAConfig cfg, List<Reported> obs, int nextIdx, List<int> newRho) {
  if (!cfg.useFollowingMoveTest) return true;
  if (nextIdx >= obs.length) return true;
  final nextSolverFace = newRho[obs[nextIdx].face];
  return nextSolverFace != F && nextSolverFace != B;
}

// ---------------------------------------------------------------------------
// Method B: beam search + structural scoring
// ---------------------------------------------------------------------------

class Weights {
  final double costSlice;
  final double costWide;
  final double costHalf;
  final List<double> faceCost; // indexed by face
  final double sliceThenFB; // the owner's ergonomic term
  final double consecutiveSameFace;
  final double conjugateBonus;
  final bool allowWide;
  final bool requireIdentityDrift;
  const Weights({
    this.costSlice = 0.6,
    this.costWide = 2.2,
    this.costHalf = 0.15,
    this.faceCost = const [0.0, 0.35, 0.35, 0.0, 0.9, 0.9],
    this.sliceThenFB = 1.4,
    this.consecutiveSameFace = 4.0,
    this.conjugateBonus = 0.85,
    this.allowWide = true,
    this.requireIdentityDrift = true,
  });

  Weights copyWith({
    List<double>? faceCost,
    double? sliceThenFB,
    double? conjugateBonus,
    bool? allowWide,
    bool? requireIdentityDrift,
  }) =>
      Weights(
        costSlice: costSlice,
        costWide: costWide,
        costHalf: costHalf,
        faceCost: faceCost ?? this.faceCost,
        sliceThenFB: sliceThenFB ?? this.sliceThenFB,
        consecutiveSameFace: consecutiveSameFace,
        conjugateBonus: conjugateBonus ?? this.conjugateBonus,
        allowWide: allowWide ?? this.allowWide,
        requireIdentityDrift: requireIdentityDrift ?? this.requireIdentityDrift,
      );
}

class _Partial {
  final int i;
  final List<int> rho;
  final List<Move> moves;
  final double cost;
  _Partial(this.i, this.rho, this.moves, this.cost);
}

int _faceOf(Move m) => m.kind == MoveKind.slice
    ? [R, U, F][m.id] // representative axis face, for same-face checks
    : m.id;

/// Incremental cost of appending [m] to [prev].
double _moveCost(Weights w, List<Move> prev, Move m) {
  var c = 0.0;
  switch (m.kind) {
    case MoveKind.slice:
      c += w.costSlice;
      break;
    case MoveKind.wide:
      c += w.costWide;
      break;
    case MoveKind.outer:
      c += w.faceCost[m.id];
      break;
    case MoveKind.rotation:
      c += 100.0;
      break;
  }
  if (m.amount == 2) c += w.costHalf;

  if (prev.isNotEmpty) {
    final last = prev.last;
    if (last.kind == m.kind && _faceOf(last) == _faceOf(m)) {
      c += w.consecutiveSameFace;
    }
    // The owner's rule: a slice is rarely followed by F/B.
    if (last.kind == MoveKind.slice &&
        m.kind == MoveKind.outer &&
        (m.id == F || m.id == B)) {
      c += w.sliceThenFB;
    }
  }

  // Conjugate / setup structure: reward X ... X' within a short span.
  for (var k = prev.length - 1, span = 0; k >= 0 && span < 5; k--, span++) {
    final p = prev[k];
    if (p.kind == m.kind && _faceOf(p) == _faceOf(m)) {
      final isInverse = (p.amount == inverseAmount(m.amount)) ||
          (p.amount == 2 && m.amount == 2);
      if (isInverse && span > 0) c -= w.conjugateBonus;
      break;
    }
  }
  return c;
}

class MethodBResult {
  final List<Move> best;
  final double margin; // cost gap to the best differing parse
  const MethodBResult(this.best, this.margin);
}

MethodBResult methodB(List<Reported> obs, Weights w, {int beam = 400}) {
  final agenda = List<List<_Partial>>.generate(obs.length + 1, (_) => <_Partial>[]);
  agenda[0].add(_Partial(0, identity, const [], 0.0));
  final finished = <_Partial>[];

  for (var i = 0; i <= obs.length; i++) {
    var here = agenda[i];
    if (here.isEmpty) continue;
    here.sort((a, b) => a.cost.compareTo(b.cost));
    if (here.length > beam) here = here.sublist(0, beam);

    for (final p in here) {
      if (i == obs.length) {
        if (!w.requireIdentityDrift || rotKey(p.rho) == rotKey(identity)) {
          finished.add(p);
        }
        continue;
      }
      final a = obs[i];
      final b = i + 1 < obs.length ? obs[i + 1] : null;

      void push(int consumed, Move m, List<int> drift) {
        final cost = p.cost + _moveCost(w, p.moves, m);
        agenda[i + consumed].add(_Partial(
          i + consumed,
          drift.isEmpty ? p.rho : compose(drift, p.rho),
          [...p.moves, m],
          cost,
        ));
      }

      // 1. single outer quarter turn
      push(1, Move(MoveKind.outer, p.rho[a.face], a.prime ? 3 : 1), const []);

      // 2. outer half turn
      if (b != null &&
          b.face == a.face &&
          b.prime == a.prime &&
          b.tMs - a.tMs <= kHalfWindowMs) {
        push(2, Move(MoveKind.outer, p.rho[a.face], 2), const []);
      }

      // 3. wide quarter / half (sensed = the opposite face)
      if (w.allowWide) {
        final wf = oppositeFace[p.rho[a.face]]!;
        final wm = Move(MoveKind.wide, wf, a.prime ? 3 : 1);
        push(1, wm, decompose(wm).drift);
        if (b != null &&
            b.face == a.face &&
            b.prime == a.prime &&
            b.tMs - a.tMs <= kHalfWindowMs) {
          final wm2 = Move(MoveKind.wide, wf, 2);
          push(2, wm2, decompose(wm2).drift);
        }
      }

      // 4. slice quarter
      if (b != null && b.tMs - a.tMs <= kSliceWindowMs) {
        final f1 = p.rho[a.face], f2 = p.rho[b.face];
        if (oppositeFace[f1] == f2) {
          final m = matchSlice(f1, a.prime ? 3 : 1, f2, b.prime ? 3 : 1);
          if (m != null) push(2, m, decompose(m).drift);
        }
      }

      // 5. slice half (4-cluster)
      if (i + 3 < obs.length && obs[i + 3].tMs - a.tMs <= kSliceWindowMs) {
        final m = matchSliceHalf([
          for (var k = i; k < i + 4; k++)
            (face: p.rho[obs[k].face], prime: obs[k].prime)
        ]);
        if (m != null) push(4, m, decompose(m).drift);
      }
    }
  }

  if (finished.isEmpty) return const MethodBResult([], 0.0);
  finished.sort((a, b) => a.cost.compareTo(b.cost));
  final best = finished.first;
  var margin = double.infinity;
  final bestStr = algToString(best.moves);
  for (final f in finished.skip(1)) {
    if (algToString(f.moves) != bestStr) {
      margin = f.cost - best.cost;
      break;
    }
  }
  return MethodBResult(best.moves, margin);
}
