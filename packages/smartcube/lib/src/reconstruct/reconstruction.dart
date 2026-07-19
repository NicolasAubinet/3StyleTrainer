/// Turns a cube's reported quarter-turn stream back into what the solver
/// thinks they did — recovering slice moves that the cube can only report as
/// two opposite face turns.
///
/// The problem: a physical `E` slice rotates the core, so the cube senses it as
/// `U + D'` and reports every *subsequent* move on a rotated frame. A
/// two-handed `U D'` senses identically but does not rotate anything. Telling
/// them apart is not possible from one pair of turns; it needs the whole
/// sequence, because the choice relabels everything after it.
///
/// So this is a global parse — a beam search over the 24 orientations — not a
/// local pattern match. Timing proposes (which turns were one physical motion),
/// structure disposes (which reading produces a plausible alg).
///
/// **Display-only.** Nothing here affects move tracking or completion
/// detection. When it is unsure it says so rather than guessing, because a
/// confidently wrong replay misleads the user about what they did.
library;

import '../model/cube_move.dart';
import 'frame_algebra.dart';
import 'move_prior.dart';
import 'solver_move.dart';

/// Turns closer together than this belong to one physical motion.
///
/// Measured on a MoYu V10: within-motion spreads sit under 20ms and between
/// motion gaps over 90ms, with an empty valley either side of 60ms.
const int kMotionGapMs = 60;

class Reconstruction {
  /// The reconstruction, or the plain outer-face reading when [abstained].
  final List<SolverMove> moves;

  /// True when the parse was not confident enough to commit. [moves] then holds
  /// the raw reading — what the cube literally reported, frame-corrected.
  final bool abstained;

  /// True when the cube's timing was too poor to segment reliably. The result
  /// may still be right, but its confidence is not meaningful.
  final bool degraded;

  /// Cost gap in nats to the best differing parse. Higher is safer. Note this
  /// measures scoring ambiguity only — it does NOT detect bad input timing,
  /// which is what [degraded] is for.
  final double margin;

  final String? note;

  const Reconstruction({
    required this.moves,
    this.abstained = false,
    this.degraded = false,
    this.margin = 0,
    this.note,
  });

  String get notation => movesToString(moves);
}

/// Reconstruct [moves] into solver notation.
///
/// [startOrientation] is **required and must be correct**. The parse is only
/// determined up to a rotation, so it cannot be inferred: the face-frequency
/// prior will happily pick whichever rotation lands the moves on R and U. Real
/// captures show solvers reorienting the cube between cases, so pass the
/// orientation that applies to *this* sequence, not one cached per session.
Reconstruction reconstruct(
  List<CubeMove> moves, {
  required FaceRotation startOrientation,
  required TimingQuality timing,
  ReconstructionWeights weights = const ReconstructionWeights(),
  double abstainBelowMargin = 1.0,
  int beamWidth = 250,
}) {
  final raw = _rawReading(moves, startOrientation);
  if (moves.isEmpty) return Reconstruction(moves: raw);

  if (timing == TimingQuality.none) {
    return Reconstruction(
      moves: raw,
      abstained: true,
      degraded: true,
      note: 'this cube has no usable per-move clock, so turns cannot be grouped '
          'into physical motions; showing the raw reading',
    );
  }

  final motions = segmentMotions(moves);
  var frontier = <_Partial>[_Partial(startOrientation, const [], 0)];

  for (final motion in motions) {
    final next = <_Partial>[];
    for (final p in frontier) {
      for (final reading in _readMotion(motion, p.rho, weights)) {
        var cost = p.cost;
        final acc = List<SolverMove>.from(p.moves);
        for (final m in reading.moves) {
          cost += _moveCost(weights, acc, m);
          acc.add(m);
        }
        next.add(_Partial(compose(reading.drift, p.rho), acc, cost));
      }
    }
    if (next.isEmpty) return Reconstruction(moves: raw, abstained: true);
    next.sort((a, b) => a.cost.compareTo(b.cost));
    frontier = next.length > beamWidth ? next.sublist(0, beamWidth) : next;
  }

  // Net drift should return to where it started — but softly. One M2 leaves the
  // core rotated by 180 degrees, and M2-method solvers live with that.
  final home = orientationKey(startOrientation);
  final scored = frontier
      .map((p) => _Partial(p.rho, p.moves,
          p.cost + (orientationKey(p.rho) == home ? 0 : weights.driftPenalty)))
      .toList()
    ..sort((a, b) => a.cost.compareTo(b.cost));

  final best = collapseDoubles(scored.first.moves);
  final bestText = movesToString(best);
  var margin = double.infinity;
  for (final s in scored.skip(1)) {
    if (movesToString(collapseDoubles(s.moves)) != bestText) {
      margin = s.cost - scored.first.cost;
      break;
    }
  }

  final degraded = timing == TimingQuality.coarse;
  if (margin < abstainBelowMargin) {
    return Reconstruction(
      moves: raw,
      abstained: true,
      degraded: degraded,
      margin: margin,
      note: 'two readings of these turns are nearly equally likely',
    );
  }
  return Reconstruction(
    moves: best,
    degraded: degraded,
    margin: margin,
    note: degraded
        ? 'this cube\'s timestamps are coarse, so motion grouping is unreliable '
            'and the confidence above should not be trusted'
        : null,
  );
}

/// Every reported turn read as a plain outer turn, corrected into the solver's
/// frame. What the replay showed before any of this existed.
List<SolverMove> _rawReading(List<CubeMove> moves, FaceRotation rho) =>
    collapseDoubles([
      for (final m in moves)
        SolverMove.outer(toSolverFrame(m.face, rho), m.prime ? 3 : 1)
    ]);

/// Group reported turns into the physical motions that produced them.
List<List<CubeMove>> segmentMotions(List<CubeMove> moves,
    {int gapMs = kMotionGapMs}) {
  final out = <List<CubeMove>>[];
  for (final m in moves) {
    final gap = out.isEmpty
        ? null
        : m.cubeTimestamp.inMilliseconds -
            out.last.last.cubeTimestamp.inMilliseconds;
    if (gap == null || gap > gapMs) {
      out.add([m]);
    } else {
      out.last.add(m);
    }
  }
  return out;
}

class _Reading {
  final List<SolverMove> moves;
  final FaceRotation drift;
  const _Reading(this.moves, this.drift);
}

class _Partial {
  final FaceRotation rho;
  final List<SolverMove> moves;
  final double cost;
  const _Partial(this.rho, this.moves, this.cost);
}

/// Every way one motion could be read: some combination of outer turns, half
/// turns, slices and (optionally) wides.
List<_Reading> _readMotion(
    List<CubeMove> motion, FaceRotation rho, ReconstructionWeights w) {
  final n = motion.length;
  if (n > 4) {
    return [
      _Reading([
        for (final r in motion)
          SolverMove.outer(toSolverFrame(r.face, rho), r.prime ? 3 : 1)
      ], kIdentity)
    ];
  }

  final results = <_Reading>[];
  final used = List<bool>.filled(n, false);

  void recurse(List<SolverMove> acc, FaceRotation drift) {
    final first = used.indexOf(false);
    if (first < 0) {
      results.add(_Reading(List<SolverMove>.from(acc), drift));
      return;
    }
    final cur = compose(drift, rho);
    final a = motion[first];
    final fa = toSolverFrame(a.face, cur);
    final da = a.prime ? 3 : 1;

    used[first] = true;
    acc.add(SolverMove.outer(fa, da));
    recurse(acc, drift);
    acc.removeLast();

    if (w.allowWideMoves) {
      final wm = SolverMove.wide(kOpposite[fa]!, da);
      acc.add(wm);
      recurse(acc, compose(wm.drift, drift));
      acc.removeLast();
    }
    used[first] = false;

    for (var j = first + 1; j < n; j++) {
      if (used[j]) continue;
      final b = motion[j];
      final fb = toSolverFrame(b.face, cur);
      final db = b.prime ? 3 : 1;

      // Same face, same direction — one half turn.
      if (b.face == a.face && b.prime == a.prime) {
        used[first] = used[j] = true;
        acc.add(SolverMove.outer(fa, 2));
        recurse(acc, drift);
        acc.removeLast();
        if (w.allowWideMoves) {
          final wm = SolverMove.wide(kOpposite[fa]!, 2);
          acc.add(wm);
          recurse(acc, compose(wm.drift, drift));
          acc.removeLast();
        }
        used[first] = used[j] = false;
      }

      // Opposite faces turned the same way in space — a slice. (Opposite faces
      // turned in opposite directions is a genuine two-handed pair, and
      // sliceForPair rejects it, which halves the candidates for free.)
      final hit = sliceForPair(fa, da, fb, db);
      if (hit != null) {
        used[first] = used[j] = true;
        final m = SolverMove.slice(hit.slice, hit.amount);
        acc.add(m);
        recurse(acc, compose(m.drift, drift));
        acc.removeLast();
        used[first] = used[j] = false;
      }
    }

    // Four turns, 2+2 on opposite faces — a half slice such as M2.
    if (n == 4 && !used.any((u) => u)) {
      final faces = motion.map((r) => r.face).toList();
      final distinct = faces.toSet().toList();
      if (distinct.length == 2 &&
          faces.where((f) => f == distinct[0]).length == 2) {
        final s = _halfSliceFor(
            toSolverFrame(distinct[0], cur), toSolverFrame(distinct[1], cur));
        if (s != null) {
          final m = SolverMove.slice(s, 2);
          results.add(_Reading([...acc, m], compose(m.drift, drift)));
        }
      }
    }
  }

  recurse(<SolverMove>[], kIdentity);
  return results;
}

Slice? _halfSliceFor(Face a, Face b) {
  if (kOpposite[a] != b) return null;
  for (final s in Slice.values) {
    final sensed = decomposeSlice(s, 2).sensed;
    if ((sensed[0].face == a && sensed[1].face == b) ||
        (sensed[0].face == b && sensed[1].face == a)) {
      return s;
    }
  }
  return null;
}

double _moveCost(
    ReconstructionWeights w, List<SolverMove> prev, SolverMove m) {
  var c = w.costOf(m);
  // The same LAYER twice in a row is what real algs never do. Deliberately not
  // the same axis: `U D'` is two different layers and a very common two-handed
  // pair, and penalising it hands every such pair to the slice reading.
  if (prev.isNotEmpty &&
      prev.last.kind == m.kind &&
      prev.last.face == m.face &&
      prev.last.slice == m.slice) {
    c += w.consecutiveSameLayer;
  }
  // Conjugate / setup structure: X ... X' within a short span.
  for (var k = prev.length - 1, span = 0; k >= 0 && span < 5; k--, span++) {
    final p = prev[k];
    if (p.kind == m.kind && p.face == m.face && p.slice == m.slice) {
      final inverse = (p.amount == inverseAmount(m.amount)) ||
          (p.amount == 2 && m.amount == 2);
      if (inverse && span > 0) c -= w.conjugateBonus;
      break;
    }
  }
  return c;
}
