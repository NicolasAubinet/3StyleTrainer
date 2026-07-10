/// A full snapshot of the cube's state.
///
/// Backed by the 54-character facelet string in URFDLB face order (the same
/// representation csTimer's `toFaceCube()` produces). A richer permutation model
/// lands with the `cube_model` port; this string is the stable interchange form
/// consumers can diff and compare.
class CubeState {
  /// 54 facelet colours, faces in URFDLB order, 9 stickers each.
  final String facelets;

  const CubeState(this.facelets);

  static const String solvedFacelets =
      'UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB';

  static const CubeState solved = CubeState(solvedFacelets);

  bool get isSolved => facelets == solvedFacelets;

  @override
  bool operator ==(Object other) =>
      other is CubeState && other.facelets == facelets;

  @override
  int get hashCode => facelets.hashCode;

  @override
  String toString() => 'CubeState($facelets)';
}
