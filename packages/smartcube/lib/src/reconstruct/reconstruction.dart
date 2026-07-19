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
import 'timing_quality.dart';

/// Turns closer together than this belong to one physical motion.
///
/// Measured on a MoYu V10: within-motion spreads sit under 20ms and between
/// motion gaps over 90ms, with an empty valley either side of 60ms.
const int kMotionGapMs = 60;

/// The longest one physical motion may last, start to finish. A four-turn half
/// slice arrives inside ~55ms, so this is generous; its job is to stop a fast
/// run of ordinary turns chaining into one unreadable blob.
const int kMotionSpanMs = 90;

/// More turns than any single motion can plausibly contain. A hand can turn two
/// layers at once, or four for a half slice — beyond that the grouping is not
/// something this parser can reason about, so it declines instead of guessing.
const int kMaxTurnsPerMotion = 4;

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

  // An over-long motion has exactly one reading, so nothing in the beam differs
  // from it and the margin would come back as infinity — maximum confidence for
  // a group we cannot actually parse. Worse, that reading declares no drift, so
  // a slice hidden inside it would misframe the whole tail. Decline instead.
  if (motions.any((m) => m.length > kMaxTurnsPerMotion)) {
    return Reconstruction(
      moves: raw,
      abstained: true,
      note: 'turns arrived too close together to tell apart; showing the raw '
          'reading',
    );
  }

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
///
/// Two bounds, not one. The per-gap check alone lets a fast run of turns chain
/// into an arbitrarily long "motion" — six turns 50ms apart became a single
/// motion, and real captures do contain gaps in that range. A physical motion
/// is at most a hand's worth of simultaneous turns, so cap its total span too.
List<List<CubeMove>> segmentMotions(List<CubeMove> moves,
    {int gapMs = kMotionGapMs, int spanMs = kMotionSpanMs}) {
  final out = <List<CubeMove>>[];
  for (final m in moves) {
    final t = m.cubeTimestamp.inMilliseconds;
    final fitsGap = out.isNotEmpty &&
        t - out.last.last.cubeTimestamp.inMilliseconds <= gapMs;
    final fitsSpan =
        out.isNotEmpty && t - out.last.first.cubeTimestamp.inMilliseconds <= spanMs;
    if (fitsGap && fitsSpan) {
      out.last.add(m);
    } else {
      out.add([m]);
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
  // reconstruct() declines before reaching here; this only guards the
  // enumeration below from a combinatorial blow-up if that ever changes.
  if (n > kMaxTurnsPerMotion) {
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

    // Four turns, 2+2 on opposite faces, each pair turned the same way — a
    // half slice such as M2. halfSliceForTurns owns the direction check.
    if (n == 4 && !used.any((u) => u)) {
      final s = halfSliceForTurns([
        for (final r in motion)
          (face: toSolverFrame(r.face, cur), prime: r.prime)
      ]);
      if (s != null) {
        final m = SolverMove.slice(s, 2);
        results.add(_Reading([...acc, m], compose(m.drift, drift)));
      }
    }
  }

  recurse(<SolverMove>[], kIdentity);
  return results;
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
