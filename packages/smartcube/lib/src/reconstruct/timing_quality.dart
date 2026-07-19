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
  /// A real per-move clock: turns within one motion arrive close enough
  /// together to be told from separate motions. The measured distribution and
  /// the threshold it justifies live on `kMotionGapMs` in reconstruction.dart —
  /// kept in one place so a re-measurement cannot update only half of it.
  perMoveClock,

  /// Timestamps exist but are coarse or noisy — batched per notification, or
  /// heavily jittered. Reconstruction still runs but flags itself degraded.
  coarse,

  /// No usable per-move timing. GoCube discards its per-move duration byte, so
  /// every move in one packet shares a timestamp. Reconstruction declines.
  none,
}
