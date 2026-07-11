import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/smart_cube/cube_orientation.dart';
import 'package:three_style_trainer/smart_cube/orientation_diagnostics.dart';
import 'package:three_style_trainer/smart_cube/three_style_geometry.dart';

const solved = CubieCube.solvedFacelet;

// The raw states the cube would report if the user held it (top, front) and
// executed [pair] correctly from a solved cube.
(String start, String end) _executed(
    String pair, CubeColour top, CubeColour front) {
  final startUser =
      CubeOrientation.normaliseFacelets(solved, top: top, front: front);
  final endUser =
      ThreeStyleGeometry.expectedAfterPair(startUser, pair, AlgType.Corner)!;
  final rawEnd =
      CubeOrientation.denormaliseFacelets(endUser, top: top, front: front);
  return (solved, rawEnd);
}

void main() {
  test('detects the holding orientation of a correctly-executed case', () {
    final (start, end) = _executed('AD', CubeColour.white, CubeColour.red);
    expect(
        detectExecutedOrientation(
            rawStart: start, rawEnd: end, pair: 'AD', algType: AlgType.Corner),
        (CubeColour.white, CubeColour.red));
  });

  test('the standard orientation resolves to white/green', () {
    final (start, end) = _executed('AD', CubeColour.white, CubeColour.green);
    expect(
        detectExecutedOrientation(
            rawStart: start, rawEnd: end, pair: 'AD', algType: AlgType.Corner),
        (CubeColour.white, CubeColour.green));
  });

  test('returns null when the execution is not the shown pair in any frame', () {
    // Cube never moved: no orientation makes AD complete.
    expect(
        detectExecutedOrientation(
            rawStart: solved,
            rawEnd: solved,
            pair: 'AD',
            algType: AlgType.Corner),
        isNull);
    // A different case (BW) executed in-frame is not AD in any orientation.
    final wrong =
        ThreeStyleGeometry.expectedAfterPair(solved, 'BW', AlgType.Corner)!;
    expect(
        detectExecutedOrientation(
            rawStart: solved,
            rawEnd: wrong,
            pair: 'AD',
            algType: AlgType.Corner),
        isNull);
  });
}
