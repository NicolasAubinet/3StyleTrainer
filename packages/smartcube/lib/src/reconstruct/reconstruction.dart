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

import 'dart:math' show max;

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

/// The widest separation across which two motions may still be fused: past
/// this, two deliberate turns is the honest reading of a sloppy slice.
const int kMaxFusionGapMs = 500;

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
  // Lowered from 1.0 with soft segmentation: correct answers now land in the
  // 0.55-0.75 band that 1.0 would discard (plan §31j).
  double abstainBelowMargin = 0.5,
  // Do NOT narrow this to buy back latency: dropping the runner-up inflates
  // the margin — at 64 a decline became a confident wrong answer (plan §31j).
  int beamWidth = 250,
  // Assert that the parse's net drift closes (completed solves only — a case
  // cannot complete otherwise, since Δ_pair never moves centres). See §31k.
  bool requireClosedDrift = false,
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

  // Do-undo pairs matched with a stack: a motion cancels the nearest UNMATCHED
  // motion before it, so nesting falls out naturally — in U R F F' R' U' the
  // F F' pair matches first, which lets R' match R and U' match U. Matching
  // through unmatched real moves is deliberately impossible: X ... X' around
  // real content is conjugate structure, not a correction. The outer members
  // of a nested pair see each other in an unchanged frame because everything
  // between them is matched and nets to identity.
  final pairOf = List<int?>.filled(motions.length, null);
  {
    final open = <int>[];
    for (var i = 0; i < motions.length; i++) {
      if (open.isNotEmpty && _cancels(motions[open.last], motions[i])) {
        pairOf[open.last] = i;
        pairOf[i] = open.last;
        open.removeLast();
      } else {
        open.add(i);
      }
    }
  }

  // Motions are atoms, never split; the search instead chooses how many
  // adjacent motions to fuse, priced by motionFusionCost rather than gated —
  // a hard gate leaves a split slice with no correct parse in the beam (§31j).
  final at = List<List<_Partial>>.generate(motions.length + 1, (_) => []);
  at[0] = [_Partial(startOrientation, const [], 0)];

  for (var i = 0; i < motions.length; i++) {
    if (at[i].isEmpty) continue;
    at[i].sort((a, b) => a.cost.compareTo(b.cost));
    // Pruning blind spot, knowingly left: the drift penalty is terminal, so a
    // parse that returns home but sits past beamWidth here is lost. Fusion
    // does saturate the beam now, but at 250 nothing observed falls off.
    if (at[i].length > beamWidth) at[i] = at[i].sublist(0, beamWidth);

    // A do-undo group reads as a CORRECTION: consumed whole, no drift, no
    // structural penalties, marked for display. Priced as its plain outer
    // turns MINUS the conjugate bonus per cancelled pair — a do-undo IS the
    // cancellation structure that bonus rewards, and if it doesn't collect it
    // here the beam collects it dishonestly by spreading the pair around a
    // neighbouring same-axis move (the yÈ report: `D' D` before `u ...` won
    // as `Uw' D2 ...`). A priced hypothesis, not a gate (§31j): genuinely
    // different parses — a split slice whose half abuts its inverse face —
    // still compete on merit, while leaving the hypothesis out pairs those
    // quarters into slices with the REAL alg moves and manufactures near-ties
    // (a solve prefixed L' L abstained to raw). Every nesting level gets its
    // own advance; when a whole group cancels, the full-group reading ties the
    // inner-pair one and the earliest-correction tie-break takes the group.
    final j = pairOf[i];
    if (j != null && j > i) {
      final group = motions.sublist(i, j + 1);
      for (final p in at[i]) {
        var cost = p.cost - weights.conjugateBonus * (group.length ~/ 2);
        for (final t in group.expand((m) => m)) {
          cost += weights.costOf(
              SolverMove.outer(toSolverFrame(t.face, p.rho), t.prime ? 3 : 1));
        }
        at[j + 1].add(_Partial(
            p.rho, [...p.moves, ..._spellCorrection(group, p.rho)], cost));
      }
    }

    final window = <CubeMove>[];
    final windowAtoms = <int>[];
    var fusionCost = 0.0;
    for (var k = 1; i + k <= motions.length; k++) {
      if (k > 1) {
        final join = motions[i + k - 1].first.cubeTimestamp.inMilliseconds -
            motions[i + k - 2].last.cubeTimestamp.inMilliseconds;
        if (join > kMaxFusionGapMs) break;
        // Clamped: a kMotionSpanMs split can leave a sub-60ms join, and
        // unclamped this would pay a bonus for re-fusing what that cap split.
        // Do NOT add a cost cutoff to bound the work either — pruning the
        // runner-up manufactures confidence (tried at 5.0 nats; plan §31j).
        fusionCost += weights.motionFusionCost *
            max(0, join - kMotionGapMs) /
            kMotionGapMs;
      }
      window.addAll(motions[i + k - 1]);
      windowAtoms.addAll(List.filled(motions[i + k - 1].length, k - 1));
      if (window.length > kMaxTurnsPerMotion) break;
      // Copied — the buffer keeps growing across k.
      final motion = List<CubeMove>.unmodifiable(window);
      final atoms = List<int>.unmodifiable(windowAtoms);
      for (final p in at[i]) {
        for (final reading in _readMotion(motion, p.rho, weights, atoms)) {
          var cost = p.cost + fusionCost;
          final acc = List<SolverMove>.from(p.moves);
          for (final m in reading.moves) {
            cost += _moveCost(weights, acc, m);
            acc.add(m);
          }
          at[i + k].add(_Partial(compose(reading.drift, p.rho), acc, cost));
        }
      }
    }
  }

  var frontier = at[motions.length];
  if (frontier.isEmpty) return Reconstruction(moves: raw, abstained: true);

  // Net drift should return to where it started — but softly. One M2 leaves the
  // core rotated by 180 degrees, and M2-method solvers live with that.
  final home = orientationKey(startOrientation);

  // A completed case ends with its centres home (see requireClosedDrift), so
  // an unclosed parse is impossible there. Filtering BEFORE the margin is what
  // makes it honest: the runner-up must be feasible too.
  if (requireClosedDrift) {
    final closed =
        frontier.where((p) => orientationKey(p.rho) == home).toList();
    // Defensive: the all-outer reading always closes, so this cannot be empty
    // unless the search itself changes shape.
    if (closed.isEmpty) return Reconstruction(moves: raw, abstained: true);
    frontier = closed;
  }
  // A pre-move pair next to an alg quarter on the same face ties exactly:
  // `(D D') Uw ...` and `Uw (D' D) ...` pair different quarters but sum the
  // same costs, and an arbitrary pick shuffles the correction around between
  // takes. Same physical claim either way, so break the tie deterministically
  // toward the account with the EARLIEST correction — a fumble before the alg
  // starts is the common case, a mistake right after the first move is not.
  final scored = frontier
      .map((p) => _Partial(p.rho, p.moves,
          p.cost + (orientationKey(p.rho) == home ? 0 : weights.driftPenalty)))
      .toList()
    ..sort((a, b) {
      final d = a.cost - b.cost;
      if (d.abs() > 1e-6) return d < 0 ? -1 : 1;
      return _firstCorrection(a.moves).compareTo(_firstCorrection(b.moves));
    });

  final collapsed = collapseDoubles(scored.first.moves);
  final simplified = simplifyAxisRuns(collapsed);
  // A botched do-undo can net to nothing at all; an empty replay helps nobody,
  // so fall back to the unsimplified reading in that case.
  final best = simplified.isEmpty ? collapsed : simplified;
  // The margin is against the best MATERIALLY different parse: same-axis moves
  // commute, so parses netting to the same per-layer rotations (`U E` vs
  // `E U`, `Rw M' R'` vs `M2`) are one physical claim in different spellings,
  // and a margin between two spellings reports a false 0.00 tie.
  final bestText = _marginKey(scored.first.moves);
  var margin = double.infinity;
  for (final s in scored.skip(1)) {
    if (_marginKey(s.moves) != bestText) {
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

/// Canonical spelling for margin comparison: net each maximal run of
/// same-axis moves and re-emit it in one fixed form.
String _marginKey(List<SolverMove> moves) =>
    movesToString(simplifyAxisRuns(moves, canonical: true));

/// Index of the first corrected move, or past-the-end when there is none.
int _firstCorrection(List<SolverMove> moves) {
  final i = moves.indexWhere((m) => m.correction);
  return i < 0 ? 1 << 20 : i;
}

/// Each reported turn as a plain outer turn in the solver's frame.
List<SolverMove> _outerTurns(List<CubeMove> moves, FaceRotation rho) => [
      for (final m in moves)
        SolverMove.outer(toSolverFrame(m.face, rho), m.prime ? 3 : 1)
    ];

/// Every reported turn read as a plain outer turn, corrected into the solver's
/// frame. What the replay showed before any of this existed.
List<SolverMove> _rawReading(List<CubeMove> moves, FaceRotation rho) =>
    collapseDoubles(_outerTurns(moves, rho));

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

/// Two adjacent motions on ONE axis whose turns cancel outright — a move (or
/// slice, or double) done and then undone. Single-axis is what makes the check
/// frame-safe: any drift a reading of the first motion could carry is about
/// that shared axis, which fixes the faces the second motion reports on.
bool _cancels(List<CubeMove> a, List<CubeMove> b) {
  int? axis;
  final net = List<int>.filled(6, 0);
  for (final m in [...a, ...b]) {
    final ax = const [0, 0, 1, 1, 2, 2][m.face.index];
    if (axis != null && ax != axis) return false;
    axis = ax;
    net[m.face.index] += m.prime ? -1 : 1;
  }
  return net.every((n) => n % 4 == 0);
}

/// A do-undo group spelled for display, each motion in its natural reading
/// (a sensed opposite-pair as the slice it was, a double collapsed), all
/// marked as corrections.
List<SolverMove> _spellCorrection(
    List<List<CubeMove>> group, FaceRotation rho) {
  List<SolverMove> spell(List<CubeMove> motion) {
    final turns = [
      for (final t in motion)
        SolverMove.outer(toSolverFrame(t.face, rho), t.prime ? 3 : 1,
            correction: true)
    ];
    if (turns.length == 2) {
      final hit = sliceForPair(
          turns[0].face!, turns[0].amount, turns[1].face!, turns[1].amount);
      if (hit != null) {
        return [SolverMove.slice(hit.slice, hit.amount, correction: true)];
      }
    }
    if (turns.length == 4) {
      final s = halfSliceForTurns([
        for (final t in motion) (face: toSolverFrame(t.face, rho), prime: t.prime)
      ]);
      if (s != null) return [SolverMove.slice(s, 2, correction: true)];
    }
    return collapseDoubles(turns);
  }

  return [for (final m in group) ...spell(m)];
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
    List<CubeMove> motion, FaceRotation rho, ReconstructionWeights w,
    [List<int>? atoms]) {
  final n = motion.length;
  // reconstruct() declines before reaching here; this only guards the
  // enumeration below from a combinatorial blow-up if that ever changes.
  if (n > kMaxTurnsPerMotion) {
    return [_Reading(_outerTurns(motion, rho), kIdentity)];
  }

  // Within one true motion (~60ms) quarter arrival order is arbitrary and
  // pairing is a free-for-all (§31h). A FUSED window's atoms are separate
  // motions in real time order: pairing across an intervening CROSS-AXIS
  // quarter claims an execution that order rules out (an S' whose halves
  // bracket a U — the Q parity bug), while a skipped SAME-AXIS quarter
  // commutes with the pair, which slice-heavy algs legitimately do.
  int axisOf(Face f) => const [0, 0, 1, 1, 2, 2][f.index];
  bool mayPair(int i, int j) {
    if (atoms == null || atoms[j] - atoms[i] <= 1) return true;
    final axis = axisOf(motion[i].face);
    for (var q = 0; q < n; q++) {
      if (atoms[q] > atoms[i] &&
          atoms[q] < atoms[j] &&
          axisOf(motion[q].face) != axis) {
        return false;
      }
    }
    return true;
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
      if (used[j] || !mayPair(first, j)) continue;
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
    // half slice such as M2. halfSliceForTurns owns the direction check. No
    // atom constraint: all four quarters are consumed, nothing is skipped,
    // and a valid half slice's quarters all share one axis anyway.
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
  // The same reading can be reached by different index pairings — `R L' R L'`
  // enumerates `M M` twice. Duplicates only burn beam slots.
  final seen = <String>{};
  return [
    for (final r in results)
      if (seen.add('${movesToString(r.moves)}|${orientationKey(r.drift)}')) r
  ];
}

double _moveCost(
    ReconstructionWeights w, List<SolverMove> prev, SolverMove m) {
  var c = w.costOf(m);
  // Corrections are invisible to the structural priors: what the alg pairs
  // with is the solver's real previous move, not the mistake they undid.
  SolverMove? last;
  for (var k = prev.length - 1; k >= 0; k--) {
    if (!prev[k].correction) {
      last = prev[k];
      break;
    }
  }
  // An outer turn after a slice draws from the conditional face distribution:
  // real algs pair slices with U/R/L, relabelled misreadings put F/B/D there.
  if (w.useAfterSlicePrior &&
      m.kind == MoveKind.outer &&
      last != null &&
      last.kind == MoveKind.slice) {
    c += w.afterSliceFaceCost[m.face!.index] - w.faceCost[m.face!.index];
  }
  // One backward walk to the previous real move on m's LAYER decides between
  // two structural signals:
  //
  // - Everything between commutes with m (same axis, or nothing): the bracket
  //   is VACUOUS — it nets straight into m, and real algs never write that.
  //   The same-layer-twice penalty made commute-aware: `D' Uw D` is as
  //   impossible in an alg as `D' D` (unpenalised, it let a do-undo pair hide
  //   around a same-axis wide — the yÈ report). Deliberately per LAYER, not
  //   axis: `U D'` is a very common two-handed pair. Adjacent same-direction
  //   quarters stay exempt — that is just how a double is executed, and
  //   collapseDoubles merges them.
  //
  // - A cross-axis move sits between: genuine conjugate / setup structure,
  //   `X ... X'` rewarded. Wides look further back — a wide is a setup move,
  //   so its undo brackets the whole conjugate (`u ... u'` spans 5-9 moves);
  //   outer/slice cancellations sit close.
  final maxSpan = m.kind == MoveKind.wide ? 12 : 5;
  var sameAxisOnly = true;
  for (var k = prev.length - 1, span = 0; k >= 0 && span < maxSpan; k--) {
    final p = prev[k];
    if (p.correction) continue;
    if (p.kind == m.kind && p.face == m.face && p.slice == m.slice) {
      if (sameAxisOnly) {
        if (!(span == 0 && m.amount != 2 && p.amount == m.amount)) {
          c += w.consecutiveSameLayer;
        }
      } else if (p.amount == inverseAmount(m.amount) ||
          (p.amount == 2 && m.amount == 2)) {
        c -= w.conjugateBonus;
      }
      break;
    }
    if (moveAxis(p) != moveAxis(m)) sameAxisOnly = false;
    span++;
  }
  return c;
}
