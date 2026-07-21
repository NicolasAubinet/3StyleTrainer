/// The scoring priors for reconstruction, as negative log probabilities.
///
/// **This is the strongest term in the method** — removing the face-frequency
/// prior drops whole-sequence accuracy from ~93% to ~45%. The costs below are
/// fitted from blddb's manmade alg database (github.com/nbwzx/blddb, GPL-3.0):
/// ~13k human 3-style algorithms weighted by how many solvers use each,
/// rotation-containing algs excluded (a rotation emits nothing, so no parse of
/// a sensed stream can contain one). Fitting is tool/slice_eval/blddb.dart.
/// Per-user statistics from recorded solves would still be better.
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

  /// Score an outer turn that FOLLOWS a slice with [afterSliceFaceCost]
  /// instead of [faceCost]. Real algs pair slices with U/R/L and almost never
  /// with F/B/D, and relabelled misreadings do the opposite — so the
  /// conditional distribution separates them where the marginal cannot.
  ///
  /// **Solve path only.** Decisive there, but WITHOUT the closed-drift filter
  /// it misreads execution styles whose slice pairings differ from the
  /// population's (measured: edge cases drop 100 -> 93.8 exact on the mistake
  /// path). Off by default.
  final bool useAfterSlicePrior;

  /// -log P(face | previous move was a slice), indexed by [Face]. Only
  /// consulted when [useAfterSlicePrior] is set.
  final List<double> afterSliceFaceCost;

  /// Cost of reading two motions [kMotionGapMs] apart as one, per further
  /// [kMotionGapMs] of separation. Timing prices the grouping rather than
  /// gating it: a sticky slice lands its halves 120-350ms apart (measured,
  /// MoYu V10) and a hard gate makes the correct parse unreachable. Lower
  /// favours slices, higher favours separate turns (plan §31j).
  final double motionFusionCost;

  const ReconstructionWeights({
    // Fitted from blddb by tool/slice_eval/blddb.dart. Transcribed exactly —
    // these are -log probabilities and the parse is sensitive to their ratios,
    // so do not round them by hand.
    this.faceCost = const [1.1693, 1.8595, 2.4657, 0.9045, 3.3882, 4.5836],
    this.outerCost = 0.1997,
    this.sliceCost = 1.9357,
    this.wideCost = 3.3048,
    this.halfCost = 2.1835,
    this.quarterCost = 0.1195,
    this.consecutiveSameLayer = 3.0,
    this.conjugateBonus = 1.0,
    this.driftPenalty = 2.0,
    this.allowWideMoves = false,
    this.useAfterSlicePrior = false,
    this.afterSliceFaceCost = const [
      1.1624, 3.7162, 1.5303, 0.8370, 4.6209, 5.6333 // U D L R F B, blddb
    ],
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
