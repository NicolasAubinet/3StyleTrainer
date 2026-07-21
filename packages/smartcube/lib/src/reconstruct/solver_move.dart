/// A move in the SOLVER's frame — what the person holding the cube thinks they
/// did — as opposed to [CubeMove], which is what the cube reported in its own
/// core-relative frame.
library;

import '../model/cube_move.dart';
import 'frame_algebra.dart';

enum MoveKind { outer, slice, wide }

/// `amount` is quarter turns clockwise: 1, 2 (a half turn), or 3 (prime).
class SolverMove {
  final MoveKind kind;

  /// The face for [MoveKind.outer] and [MoveKind.wide].
  final Face? face;

  /// The layer for [MoveKind.slice].
  final Slice? slice;

  final int amount;

  /// True for a move that was done and then undone — a mistake the solver
  /// corrected. Displayed in parentheses and never merged with real moves.
  final bool correction;

  const SolverMove.outer(Face this.face, this.amount, {this.correction = false})
      : kind = MoveKind.outer,
        slice = null;

  const SolverMove.wide(Face this.face, this.amount, {this.correction = false})
      : kind = MoveKind.wide,
        slice = null;

  const SolverMove.slice(Slice this.slice, this.amount,
      {this.correction = false})
      : kind = MoveKind.slice,
        face = null;

  String get notation {
    final suffix = amount == 1 ? '' : (amount == 2 ? '2' : "'");
    return switch (kind) {
      MoveKind.outer => '${face!.name}$suffix',
      MoveKind.wide => '${face!.name}w$suffix',
      MoveKind.slice => '${slice!.name}$suffix',
    };
  }

  /// The drift this move imparts on the reporting frame.
  FaceRotation get drift => switch (kind) {
        MoveKind.outer => kIdentity,
        MoveKind.slice => decomposeSlice(slice!, amount).drift,
        MoveKind.wide => decomposeWide(face!, amount).drift,
      };

  SolverMove withAmount(int a) => switch (kind) {
        MoveKind.outer => SolverMove.outer(face!, a, correction: correction),
        MoveKind.wide => SolverMove.wide(face!, a, correction: correction),
        MoveKind.slice => SolverMove.slice(slice!, a, correction: correction),
      };

  @override
  String toString() => notation;

  @override
  bool operator ==(Object other) =>
      other is SolverMove &&
      other.kind == kind &&
      other.face == face &&
      other.slice == slice &&
      other.amount == amount &&
      other.correction == correction;

  @override
  int get hashCode => Object.hash(kind, face, slice, amount, correction);
}

/// Corrected mistakes render in parentheses: `(L' L) M' U ...`.
String movesToString(List<SolverMove> moves) {
  final buf = StringBuffer();
  for (var i = 0; i < moves.length; i++) {
    final m = moves[i];
    if (buf.isNotEmpty) buf.write(' ');
    if (m.correction && (i == 0 || !moves[i - 1].correction)) buf.write('(');
    buf.write(m.notation);
    if (m.correction && (i == moves.length - 1 || !moves[i + 1].correction)) {
      buf.write(')');
    }
  }
  return buf.toString();
}

/// The rotation axis a move turns about: 0 = U/D/E, 1 = L/R/M, 2 = F/B/S.
int moveAxis(SolverMove m) => m.kind == MoveKind.slice
    ? const [1, 0, 2][m.slice!.index]
    : const [0, 0, 1, 1, 2, 2][m.face!.index];

const _kPosFace = [Face.U, Face.R, Face.F];
const _kNegFace = [Face.D, Face.L, Face.B];
const _kSlice = [Slice.E, Slice.M, Slice.S];

/// Which way the axis's slice turns relative to its positive face: M follows
/// L and E follows D (against R and U), S follows F (with it).
const _kSliceSign = [-1, -1, 1];

/// Net each maximal run of same-axis moves and re-emit it in the fewest moves.
///
/// The three layers on one axis commute — each rotates independently — so a
/// perfectly captured `Rw M' R'` IS an `M2`, and `R' M` is `Rw'`. By default a
/// run is only replaced when the net spelling is strictly shorter, so already
/// minimal executions like `R M'` keep their captured order. With [canonical]
/// every run is re-spelt, giving one fixed spelling per physical claim — for
/// comparing parses, not for display.
List<SolverMove> simplifyAxisRuns(List<SolverMove> moves,
    {bool canonical = false}) {
  var cur = moves;
  while (true) {
    final next = _simplifyPass(cur, canonical);
    if (movesToString(next) == movesToString(cur)) return next;
    // A run cancelled out entirely, so its same-axis neighbours may now touch.
    cur = next;
  }
}

List<SolverMove> _simplifyPass(List<SolverMove> moves, bool canonical) {
  final out = <SolverMove>[];
  var i = 0;
  while (i < moves.length) {
    final axis = moveAxis(moves[i]);
    var j = i + 1;
    // For display a correction is a barrier: it must stay visible, not net
    // away against the real moves around it. Canonical mode nets through it —
    // every competing parse carries the same corrections, so keys still match.
    while (j < moves.length &&
        moveAxis(moves[j]) == axis &&
        (canonical || moves[j].correction == moves[i].correction)) {
      j++;
    }
    final run = moves.sublist(i, j);
    if (!canonical && run.first.correction) {
      out.addAll(run);
      i = j;
      continue;
    }
    final net = _netRun(run, axis);
    out.addAll(canonical || net.length < run.length ? net : run);
    i = j;
  }
  return out;
}

/// The fewest-move spelling of [run]'s net effect: quarter turns per layer
/// mod 4 (measured in the positive face's direction), a wide move where an
/// outer layer and the middle turn together, singles for the rest.
List<SolverMove> _netRun(List<SolverMove> run, int axis) {
  var hi = 0, mid = 0, lo = 0;
  for (final m in run) {
    switch (m.kind) {
      case MoveKind.outer:
        if (m.face == _kPosFace[axis]) {
          hi += m.amount;
        } else {
          lo -= m.amount;
        }
      case MoveKind.slice:
        mid += _kSliceSign[axis] * m.amount;
      case MoveKind.wide:
        if (m.face == _kPosFace[axis]) {
          hi += m.amount;
          mid += m.amount;
        } else {
          lo -= m.amount;
          mid -= m.amount;
        }
    }
  }
  hi %= 4;
  mid %= 4;
  lo %= 4;
  final out = <SolverMove>[];
  if (hi != 0 && hi == mid) {
    out.add(SolverMove.wide(_kPosFace[axis], hi));
    hi = mid = 0;
  } else if (lo != 0 && lo == mid) {
    out.add(SolverMove.wide(_kNegFace[axis], 4 - lo));
    lo = mid = 0;
  }
  if (hi != 0) out.add(SolverMove.outer(_kPosFace[axis], hi));
  if (mid != 0) {
    out.add(SolverMove.slice(
        _kSlice[axis], _kSliceSign[axis] == 1 ? mid : 4 - mid));
  }
  if (lo != 0) out.add(SolverMove.outer(_kNegFace[axis], 4 - lo));
  return out;
}

/// Two consecutive quarter turns of the same layer in the same direction ARE a
/// half turn — the cube cannot distinguish `M' M'` from `M2`, and neither
/// should the output. Observed on real hardware: doubles are routinely executed
/// as two quarter turns.
List<SolverMove> collapseDoubles(List<SolverMove> moves) {
  final out = <SolverMove>[];
  for (final m in moves) {
    if (out.isNotEmpty && m.amount != 2) {
      final p = out.last;
      if (p.kind == m.kind &&
          p.face == m.face &&
          p.slice == m.slice &&
          p.amount == m.amount &&
          p.correction == m.correction) {
        out[out.length - 1] = m.withAmount(2);
        continue;
      }
    }
    out.add(m);
  }
  return out;
}
