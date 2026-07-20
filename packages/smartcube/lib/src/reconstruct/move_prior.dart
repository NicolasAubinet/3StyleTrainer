/// The scoring priors for reconstruction, as negative log probabilities.
///
/// **This is the weakest part of the method and the strongest term in it.**
/// Removing the face-frequency prior drops whole-sequence accuracy from ~93% to
/// ~45%, and the numbers below are fitted from a hand-written corpus of ~64
/// blind sequences, not from a large real-world sample. Treat them as a
/// starting point to be replaced by per-user statistics, not as constants.
library;

import '../model/cube_move.dart';
import 'solver_move.dart';

/// Scoring weights. Defaults were tuned on synthetic data with a held-out
/// split; the ablations behind them are more trustworthy than the exact values.
class ReconstructionWeights {
  /// -log P(face) for an outer turn, indexed by [Face].
  final List<double> faceCost;

  final double outerCost;
  final double sliceCost;
  final double wideCost;
  final double halfCost;
  final double quarterCost;

  /// Real algs almost never turn the same layer twice in a row.
  final double consecutiveSameLayer;

  /// Reward `X ... X'` within a short span. Conjugate and setup structure is
  /// the strongest method-agnostic signal available — CFOP and Roux algs have
  /// it too, so this does not bake in 3-style assumptions.
  final double conjugateBonus;

  /// Penalty for a parse whose net drift does not return to where it started.
  ///
  /// **Soft, deliberately.** A single `M2` leaves the core rotated by 180 and
  /// M2-method solvers live with that between pairs, so a hard constraint is
  /// wrong. Enforcing it strictly costs ~8 points of accuracy; dropping it
  /// entirely costs ~9.
  final double driftPenalty;

  /// Wide moves have NO local signature — a wide senses as a single turn on the
  /// opposite face, indistinguishable from an ordinary turn except by its
  /// effect on everything after it. Off by default: blind solving barely uses
  /// them, and allowing them costs accuracy on the cases that matter.
  final bool allowWideMoves;

  /// Cost of reading two motions [kMotionGapMs] apart as one, per further
  /// [kMotionGapMs] of separation. Timing prices the grouping rather than
  /// gating it: a sticky slice lands its halves 120-350ms apart (measured,
  /// MoYu V10) and a hard gate makes the correct parse unreachable. Lower
  /// favours slices, higher favours separate turns (plan §31j).
  final double motionFusionCost;

  const ReconstructionWeights({
    // Fitted from the corpus in tool/slice_eval. Transcribed exactly — these
    // are -log probabilities and the parse is sensitive to their ratios, so do
    // not round them by hand.
    this.faceCost = const [0.9272, 2.2219, 2.5435, 1.0204, 3.0204, 4.8122],
    this.outerCost = 0.2032,
    this.sliceCost = 1.8662,
    this.wideCost = 3.5354,
    this.halfCost = 2.3369,
    this.quarterCost = 0.1016,
    this.consecutiveSameLayer = 3.0,
    this.conjugateBonus = 1.0,
    this.driftPenalty = 2.0,
    this.allowWideMoves = false,
    this.motionFusionCost = 1.0,
  });

  double costOf(SolverMove m) {
    var c = switch (m.kind) {
      MoveKind.outer => outerCost + faceCost[m.face!.index],
      MoveKind.slice => sliceCost,
      MoveKind.wide => wideCost + faceCost[m.face!.index],
    };
    c += m.amount == 2 ? halfCost : quarterCost;
    return c;
  }
}
