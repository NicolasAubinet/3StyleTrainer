/// How much a cube's per-move timestamps can be trusted.
///
/// Slice reconstruction decides which turns belong to one physical motion by
/// timing — that is what separates a slice from two turns done at once. So a
/// cube's clock quality decides whether reconstruction is possible at all.
///
/// This has to be declared rather than measured. Degrading timestamps lowers
/// accuracy without lowering the parser's confidence: at ~100ms granularity
/// accuracy falls to roughly 77% while the reported margin stays high, so
/// nothing downstream can notice on its own.
library;

enum TimingQuality {
  /// A real per-move clock. Measured on a MoYu V10: turns within one motion
  /// land under 20ms apart, separate motions over 90ms, with a clean valley
  /// between (see [kMotionGapMs]).
  perMoveClock,

  /// Timestamps exist but are coarse or noisy — batched per notification, or
  /// heavily jittered. Reconstruction still runs but flags itself degraded.
  coarse,

  /// No usable per-move timing. GoCube discards its per-move duration byte, so
  /// every move in one packet shares a timestamp. Reconstruction declines.
  none,
}
