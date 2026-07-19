import 'package:smartcube/smartcube.dart' as sc;

import '../settings.dart';
import 'cube_orientation.dart';

/// Bridges the app's holding-orientation setting to the smartcube package's
/// slice reconstruction, and turns a case's raw moves into readable notation.
///
/// Without this the replay of a botched case reads `R L' U R' L U'` where the
/// solver actually did `M U M' U'`.
class MoveReconstruction {
  /// The cube's reported frame expressed as a face permutation, derived from
  /// the user's top/front colour setting.
  ///
  /// This has to be read fresh for every case rather than cached: a hardware
  /// capture showed the cube being re-oriented between one execution and the
  /// next, and the reconstruction cannot recover from a stale frame — the parse
  /// is only determined up to a rotation, so a wrong frame yields a confident
  /// answer that is silently rotated.
  static sc.FaceRotation orientationFromSettings() => orientationFor(
        top: Settings().getCubeTopColour(),
        front: Settings().getCubeFrontColour(),
      );

  /// The same mapping, without reading the settings singleton.
  static sc.FaceRotation orientationFor({
    required CubeColour top,
    required CubeColour front,
  }) =>
      [
        for (final f in sc.Face.values)
          sc.Face.values
              .byName(
                  CubeOrientation.normaliseFace(f.name, top: top, front: front))
              .index
      ];

  /// Reconstruct [moves] into solver notation, or `null` when nothing was
  /// turned.
  ///
  /// [ReplayMoves.reconstructed] is false when this is the plain outer-face
  /// reading — the cube's clock could not support grouping turns into motions,
  /// or two readings were too close to call. The notation is still honest in
  /// that case, it just claims less: slices are left as the face pairs the cube
  /// reported. Callers should not present the two identically.
  static ReplayMoves? describe(
    List<sc.CubeMove> moves, {
    required sc.SmartCube? cube,
  }) {
    if (moves.isEmpty) return null;
    final result = sc.reconstruct(
      moves,
      startOrientation: orientationFromSettings(),
      timing: cube?.timingQuality ?? sc.TimingQuality.none,
    );
    return ReplayMoves(
      notation: result.notation,
      reconstructed: !result.abstained && !result.degraded,
      why: result.note,
    );
  }
}

/// What a botched case's turns looked like, and how much to trust the reading.
class ReplayMoves {
  final String notation;

  /// False when [notation] is the raw face-by-face reading rather than a
  /// reconstruction — no slices were recovered and none should be inferred.
  final bool reconstructed;

  /// Why the reconstruction held back, when it did.
  final String? why;

  const ReplayMoves({
    required this.notation,
    required this.reconstructed,
    this.why,
  });
}
