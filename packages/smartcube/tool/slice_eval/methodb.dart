/// Method B, rebuilt: segment the stream into physical MOTIONS by timing, then
/// beam-search over the 24-orientation frame group, scoring each motion's
/// possible interpretations with fitted log-probabilities (plan §31b/c).

import 'dart:math' show max;

import 'algebra.dart';
import 'methods.dart' show matchSlice, matchSliceHalf;
import 'stats.dart';
import 'synth.dart';

/// Must track `kMotionGapMs` in lib/src/reconstruct/reconstruction.dart, which
/// carries the measurement behind the value. Deliberately a separate copy: this
/// harness exists to judge the shipped parser, so it must not import it.
const int kMotionGapMs = 60;

/// Group reported quarter turns into one physical motion each.
List<List<Reported>> segmentMotions(List<Reported> obs, {int gapMs = kMotionGapMs}) {
  final out = <List<Reported>>[];
  for (final r in obs) {
    if (out.isEmpty || r.tMs - out.last.last.tMs > gapMs) {
      out.add([r]);
    } else {
      out.last.add(r);
    }
  }
  return out;
}

/// How to apply the owner's "a slice is rarely followed by F/B" rule.
enum AfterSlice {
  off,

  /// Swap in the full fitted P(face | after slice) distribution.
  fitted,

  /// Just a flat penalty when a slice is followed by F or B.
  binary,
}

class BWeights {
  final double consecutiveSameFace;
  final double conjugateBonus;
  final double driftPenalty;
  final double afterSliceFbPenalty;
  final bool allowWide;
  final AfterSlice afterSlice;
  final bool useFacePrior;

  /// Let the search choose the grouping instead of committing upfront — hard
  /// segmentation makes a split slice unparseable (plan §31j).
  final bool softSegmentation;

  /// Cost of fusing motions [kMotionGapMs] apart, per further [kMotionGapMs];
  /// what stops the search inventing slices from genuinely separate turns.
  final double timingPenalty;

  /// Beyond this the fusion is refused outright, to bound the search.
  final int maxMotionSpanMs;

  const BWeights({
    this.consecutiveSameFace = 3.0,
    this.conjugateBonus = 1.0,
    this.driftPenalty = 2.0,
    this.afterSliceFbPenalty = 1.2,
    this.allowWide = true,
    this.afterSlice = AfterSlice.off,
    this.useFacePrior = true,
    this.softSegmentation = false,
    this.timingPenalty = 1.0,
    this.maxMotionSpanMs = 500,
  });

  BWeights copyWith({
    double? conjugateBonus,
    double? driftPenalty,
    double? afterSliceFbPenalty,
    bool? allowWide,
    AfterSlice? afterSlice,
    bool? useFacePrior,
    bool? softSegmentation,
    double? timingPenalty,
    int? maxMotionSpanMs,
  }) =>
      BWeights(
        consecutiveSameFace: consecutiveSameFace,
        conjugateBonus: conjugateBonus ?? this.conjugateBonus,
        driftPenalty: driftPenalty ?? this.driftPenalty,
        afterSliceFbPenalty: afterSliceFbPenalty ?? this.afterSliceFbPenalty,
        allowWide: allowWide ?? this.allowWide,
        afterSlice: afterSlice ?? this.afterSlice,
        useFacePrior: useFacePrior ?? this.useFacePrior,
        softSegmentation: softSegmentation ?? this.softSegmentation,
        timingPenalty: timingPenalty ?? this.timingPenalty,
        maxMotionSpanMs: maxMotionSpanMs ?? this.maxMotionSpanMs,
      );
}

/// One way of reading a motion: the moves it emits and the drift it imparts.
class _Reading {
  final List<Move> moves;
  final List<int> drift;
  const _Reading(this.moves, this.drift);
}

/// Enumerate readings of one motion under drift [rho]. [atoms] labels each
/// quarter with the atomic (~60ms) motion it arrived in (null = one true
/// motion, where arrival order is arbitrary and pairing free, §31h). In a
/// fused window a pairing may skip only SAME-axis quarters, which commute;
/// skipping a cross-axis quarter claims an execution the observed order rules
/// out (the Q-parity bug).
List<_Reading> readMotion(List<Reported> motion, List<int> rho, BWeights w,
    [List<int>? atoms]) {
  final n = motion.length;
  if (n > 4) {
    // Too long to partition; read every quarter as an outer turn.
    return [
      _Reading([
        for (final r in motion) Move(MoveKind.outer, rho[r.face], r.prime ? 3 : 1)
      ], identity)
    ];
  }
  int axisOf(int face) => const [0, 0, 1, 1, 2, 2][face];
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

  void recurse(List<Move> acc, List<int> drift) {
    var first = -1;
    for (var i = 0; i < n; i++) {
      if (!used[i]) {
        first = i;
        break;
      }
    }
    if (first < 0) {
      results.add(_Reading(List<Move>.from(acc), drift));
      return;
    }
    final cur = compose(drift, rho);
    final a = motion[first];
    final fa = cur[a.face];
    final da = a.prime ? 3 : 1;

    // (a) single quarter as an outer turn
    used[first] = true;
    acc.add(Move(MoveKind.outer, fa, da));
    recurse(acc, drift);
    acc.removeLast();

    // (b) single quarter as a wide turn
    if (w.allowWide) {
      final wm = Move(MoveKind.wide, oppositeFace[fa]!, da);
      acc.add(wm);
      recurse(acc, compose(decompose(wm).drift, drift));
      acc.removeLast();
    }
    used[first] = false;

    for (var j = first + 1; j < n; j++) {
      if (used[j] || !mayPair(first, j)) continue;
      final b = motion[j];
      final fb = cur[b.face];
      final db = b.prime ? 3 : 1;

      // (c) two quarters, same face & direction -> a half turn
      if (b.face == a.face && b.prime == a.prime) {
        used[first] = used[j] = true;
        acc.add(Move(MoveKind.outer, fa, 2));
        recurse(acc, drift);
        acc.removeLast();
        if (w.allowWide) {
          final wm = Move(MoveKind.wide, oppositeFace[fa]!, 2);
          acc.add(wm);
          recurse(acc, compose(decompose(wm).drift, drift));
          acc.removeLast();
        }
        used[first] = used[j] = false;
      }

      // (d) two quarters on opposite faces -> a slice
      if (oppositeFace[fa] == fb) {
        final m = matchSlice(fa, da, fb, db);
        if (m != null) {
          used[first] = used[j] = true;
          acc.add(m);
          recurse(acc, compose(decompose(m).drift, drift));
          acc.removeLast();
          used[first] = used[j] = false;
        }
      }
    }

    // (e) four quarters, 2+2 on opposite faces -> a half slice. No atom
    // constraint: everything is consumed, and a valid half slice's quarters
    // all share one axis anyway.
    if (n == 4 && !used.any((u) => u)) {
      final m = matchSliceHalf([
        for (final r in motion) (face: cur[r.face], prime: r.prime)
      ]);
      if (m != null) {
        results.add(_Reading([...acc, m], compose(decompose(m).drift, drift)));
      }
    }
  }

  recurse(<Move>[], identity);
  return results;
}

int _faceOf(Move m) =>
    m.kind == MoveKind.slice ? const [R, U, F][m.id] : m.id;

double moveCost(Stats st, BWeights w, List<Move> prev, Move m) {
  var c = 0.0;
  final prevWasSlice = prev.isNotEmpty && prev.last.kind == MoveKind.slice;
  switch (m.kind) {
    case MoveKind.outer:
      c += st.outerCost;
      if (w.useFacePrior) {
        if (prevWasSlice && w.afterSlice == AfterSlice.fitted) {
          c += st.afterSliceFaceCost[m.id];
        } else {
          c += st.faceCost[m.id];
          if (prevWasSlice &&
              w.afterSlice == AfterSlice.binary &&
              (m.id == F || m.id == B)) {
            c += w.afterSliceFbPenalty;
          }
        }
      }
      break;
    case MoveKind.slice:
      c += st.sliceCost;
      break;
    case MoveKind.wide:
      c += st.wideCost;
      if (w.useFacePrior) c += st.faceCost[m.id];
      break;
    case MoveKind.rotation:
      c += 50.0;
      break;
  }
  c += m.amount == 2 ? st.halfCost : st.quarterCost;

  if (prev.isNotEmpty) {
    final last = prev.last;
    if (last.kind == m.kind && _faceOf(last) == _faceOf(m)) {
      c += w.consecutiveSameFace;
    }
  }
  // Wides get a longer lookback: a wide is a setup move, so its undo brackets
  // the whole conjugate (`u ... u'` spans 5-9 moves), where outer/slice
  // cancellations sit close together. 5 stays 5 for those — tuned.
  final maxSpan = m.kind == MoveKind.wide ? 12 : 5;
  for (var k = prev.length - 1, span = 0; k >= 0 && span < maxSpan; k--, span++) {
    final p = prev[k];
    if (p.kind == m.kind && _faceOf(p) == _faceOf(m)) {
      final inv = (p.amount == inverseAmount(m.amount)) ||
          (p.amount == 2 && m.amount == 2);
      if (inv && span > 0) c -= w.conjugateBonus;
      break;
    }
  }
  return c;
}

class _P {
  final List<int> rho;
  final List<Move> moves;
  final double cost;
  _P(this.rho, this.moves, this.cost);
}

class BResult {
  final List<Move> best;
  final double margin;

  /// Total cost of the winning parse. Comparable ACROSS runs, so it is what
  /// selects between candidate initial orientations (margin is not).
  final double cost;

  /// Top distinct parses with their costs, cheapest first (diagnostics).
  final List<(String, double)> top;
  const BResult(this.best, this.margin, [this.cost = 0.0, this.top = const []]);
}

/// Timing fixes the grouping upfront, then the beam scores readings within it.
List<_P> _searchHard(
    List<Reported> obs, Stats st, BWeights w, int beam, List<int>? initial) {
  var frontier = <_P>[_P(initial ?? identity, const [], 0.0)];
  for (final motion in segmentMotions(obs)) {
    final next = <_P>[];
    for (final p in frontier) {
      for (final r in readMotion(motion, p.rho, w)) {
        next.add(_extend(p, r, st, w, 0.0));
      }
    }
    next.sort((a, b) => a.cost.compareTo(b.cost));
    frontier = next.length > beam ? next.sublist(0, beam) : next;
  }
  return frontier;
}

/// Grouping is part of the search, asymmetrically: sub-[kMotionGapMs] turns
/// stay forced into one motion (splitting them would wreck the simultaneous
/// outer pair), while adjacent motions MAY be fused at a timing cost. The
/// trade is inherent — fusable split slices mean fusable separate turns; the
/// dial is [BWeights.timingPenalty] (plan §31j).
List<_P> _searchSoft(
    List<Reported> obs, Stats st, BWeights w, int beam, List<int>? initial) {
  final atoms = segmentMotions(obs);
  final n = atoms.length;
  final at = List<List<_P>>.generate(n + 1, (_) => <_P>[]);
  at[0] = [_P(initial ?? identity, const [], 0.0)];

  for (var i = 0; i < n; i++) {
    if (at[i].isEmpty) continue;
    // Deduping clone paths here was tried: byte-identical output, so beam
    // crowding is not why the adversarial group drops (plan §31j).
    at[i].sort((a, b) => a.cost.compareTo(b.cost));
    if (at[i].length > beam) at[i] = at[i].sublist(0, beam);

    final window = <Reported>[];
    final windowAtoms = <int>[];
    var tCost = 0.0;
    for (var k = 1; i + k <= n; k++) {
      if (k > 1) {
        final join = atoms[i + k - 1].first.tMs - atoms[i + k - 2].last.tMs;
        if (join > w.maxMotionSpanMs) break;
        // Clamped, matching the lib: a span-split can leave a sub-60ms join,
        // and unclamped this would pay a bonus for re-fusing it.
        tCost += w.timingPenalty * max(0, join - kMotionGapMs) / kMotionGapMs;
      }
      window.addAll(atoms[i + k - 1]);
      windowAtoms.addAll(List.filled(atoms[i + k - 1].length, k - 1));
      if (window.length > 4) break;
      for (final p in at[i]) {
        for (final r in readMotion(window, p.rho, w, windowAtoms)) {
          at[i + k].add(_extend(p, r, st, w, tCost));
        }
      }
    }
  }
  return at[n];
}

_P _extend(_P p, _Reading r, Stats st, BWeights w, double timingCost) {
  var cost = p.cost + timingCost;
  final moves = List<Move>.from(p.moves);
  for (final m in r.moves) {
    cost += moveCost(st, w, moves, m);
    moves.add(m);
  }
  return _P(compose(r.drift, p.rho), moves, cost);
}

BResult methodBv2(List<Reported> obs, Stats st, BWeights w,
    {int beam = 250, List<int>? initial, bool requireHomeDrift = false}) {
  var frontier = w.softSegmentation
      ? _searchSoft(obs, st, w, beam, initial)
      : _searchHard(obs, st, w, beam, initial);

  if (frontier.isEmpty) return const BResult([], 0.0, double.infinity);

  // A completed case ends with the centres home (Δ_pair never moves them), so
  // for solve replays an unclosed parse is infeasible — filter BEFORE the
  // margin is measured. An empty filtered set means the vocabulary cannot
  // close the stream; fall through rather than crash (the lib abstains there).
  if (requireHomeDrift) {
    final home = rotKey(initial ?? identity);
    final closed =
        frontier.where((p) => rotKey(p.rho) == home).toList();
    if (closed.isNotEmpty) frontier = closed;
  }
  // Net drift must return to where it STARTED, not to the identity — the cube
  // is rarely held in its own canonical orientation (§31h).
  final home = rotKey(initial ?? identity);
  final scored = frontier
      .map((p) => _P(p.rho, p.moves,
          p.cost + (rotKey(p.rho) == home ? 0.0 : w.driftPenalty)))
      .toList()
    ..sort((a, b) => a.cost.compareTo(b.cost));

  final best = scored.first;
  var margin = double.infinity;
  // Margin against the best MATERIALLY different parse: canonicalCollapsed
  // equates commuting same-axis reorderings and split doubles, which are the
  // same physical claim in different notation — measuring the margin between
  // two spellings of one hypothesis reports false ambiguity (a 0.00 "tie").
  final bestStr = algToString(canonicalCollapsed(best.moves));
  for (final s in scored.skip(1)) {
    if (algToString(canonicalCollapsed(s.moves)) != bestStr) {
      margin = s.cost - best.cost;
      break;
    }
  }
  final top = <(String, double)>[];
  for (final s in scored) {
    final str = algToString(canonicalCollapsed(s.moves));
    if (top.any((t) => t.$1 == str)) continue;
    top.add((str, s.cost - best.cost));
    if (top.length >= 6) break;
  }
  return BResult(best.moves, margin, best.cost, top);
}
