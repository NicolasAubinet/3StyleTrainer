import '../alg_structs.dart';
import 'cube_orientation.dart';
import 'three_style_geometry.dart';

/// The holding orientation under which the (un-normalised) execution [rawStart]
/// → [rawEnd] is the correct [pair], or null if none — i.e. "right alg, wrong
/// orientation setting". Used only until the first case completes correctly.
(CubeColour, CubeColour)? detectExecutedOrientation({
  required String rawStart,
  required String rawEnd,
  required String pair,
  required AlgType algType,
}) {
  for (final (top, front) in CubeOrientation.allOrientations()) {
    final start =
        CubeOrientation.normaliseFacelets(rawStart, top: top, front: front);
    final end =
        CubeOrientation.normaliseFacelets(rawEnd, top: top, front: front);
    if (ThreeStyleGeometry.isPairComplete(end, start, pair, algType)) {
      return (top, front);
    }
  }
  return null;
}
