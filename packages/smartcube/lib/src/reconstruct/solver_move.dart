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

  const SolverMove.outer(Face this.face, this.amount)
      : kind = MoveKind.outer,
        slice = null;

  const SolverMove.wide(Face this.face, this.amount)
      : kind = MoveKind.wide,
        slice = null;

  const SolverMove.slice(Slice this.slice, this.amount)
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

  /// The axis this move turns, for "is this the same layer as that one" checks.
  /// A slice shares its axis with the two faces it sits between.
  int get axis => switch (kind) {
        MoveKind.slice => slice!.index,
        _ => switch (face!) {
            Face.R || Face.L => Slice.M.index,
            Face.U || Face.D => Slice.E.index,
            Face.F || Face.B => Slice.S.index,
          },
      };

  SolverMove withAmount(int a) => switch (kind) {
        MoveKind.outer => SolverMove.outer(face!, a),
        MoveKind.wide => SolverMove.wide(face!, a),
        MoveKind.slice => SolverMove.slice(slice!, a),
      };

  @override
  String toString() => notation;

  @override
  bool operator ==(Object other) =>
      other is SolverMove &&
      other.kind == kind &&
      other.face == face &&
      other.slice == slice &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(kind, face, slice, amount);
}

String movesToString(List<SolverMove> moves) =>
    moves.map((m) => m.notation).join(' ');

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
          p.amount == m.amount) {
        out[out.length - 1] = m.withAmount(2);
        continue;
      }
    }
    out.add(m);
  }
  return out;
}
