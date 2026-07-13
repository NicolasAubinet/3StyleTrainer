import 'package:smartcube/smartcube.dart';

/// Cube face colours in the driver's solved frame: U=white, R=red, F=green,
/// D=yellow, L=orange, B=blue.
enum CubeColour { white, yellow, green, blue, red, orange }

/// Rotates the cube's reported facelets from the user's holding orientation into
/// the standard white-top/green-front frame the geometry assumes. A pure
/// whole-cube rotation (positions + face relabelling); white/green is identity.
class CubeOrientation {
  static const List<String> _faces = ['U', 'R', 'F', 'D', 'L', 'B'];

  static const Map<String, CubeColour> faceColour = {
    'U': CubeColour.white,
    'R': CubeColour.red,
    'F': CubeColour.green,
    'D': CubeColour.yellow,
    'L': CubeColour.orange,
    'B': CubeColour.blue,
  };
  static final Map<CubeColour, String> _colourFace = {
    for (final e in faceColour.entries) e.value: e.key,
  };

  // 3D integer centre of each face (x=right, y=up, z=front).
  static const Map<String, _Vec> _faceCentre = {
    'U': (0, 1, 0),
    'R': (1, 0, 0),
    'F': (0, 0, 1),
    'D': (0, -1, 0),
    'L': (-1, 0, 0),
    'B': (0, 0, -1),
  };
  static final Map<_Vec, String> _centreFace = {
    for (final e in _faceCentre.entries) e.value: e.key,
  };

  // Per-facelet position + normal, from the CubieCube tables so indexing matches.
  static final List<_Vec> _pos = _buildPositions();
  static final List<_Vec> _normal =
      [for (var i = 0; i < 54; i++) _faceCentre[_faces[i ~/ 9]]!];
  static final Map<(_Vec, _Vec), int> _indexAt = {
    for (var i = 0; i < 54; i++) (_pos[i], _normal[i]): i,
  };

  static final List<_Rot> _rotations = _buildRotations();

  static _Vec _add(_Vec a, _Vec b) => (a.$1 + b.$1, a.$2 + b.$2, a.$3 + b.$3);

  static List<_Vec> _buildPositions() {
    final pos = List<_Vec>.filled(54, (0, 0, 0));
    for (var f = 0; f < 6; f++) {
      pos[f * 9 + 4] = _faceCentre[_faces[f]]!;
    }
    for (final group in [...CubieCube.cFacelet, ...CubieCube.eFacelet]) {
      final p = group.map((i) => _faceCentre[_faces[i ~/ 9]]!).reduce(_add);
      for (final i in group) {
        pos[i] = p;
      }
    }
    return pos;
  }

  // Closure of the 24 orientations under the three 90° axis rotations.
  static List<_Rot> _buildRotations() {
    const identity = _Rot((1, 0, 0), (0, 1, 0), (0, 0, 1));
    final gens = [
      const _Rot((1, 0, 0), (0, 0, 1), (0, -1, 0)), // x
      const _Rot((0, 0, -1), (0, 1, 0), (1, 0, 0)), // y
      const _Rot((0, 1, 0), (-1, 0, 0), (0, 0, 1)), // z
    ];
    final seen = <_Rot>{identity};
    final queue = <_Rot>[identity];
    while (queue.isNotEmpty) {
      final r = queue.removeLast();
      for (final g in gens) {
        final c = r.then(g);
        if (seen.add(c)) queue.add(c);
      }
    }
    return seen.toList();
  }

  /// The rotation that takes the user's holding frame (top/front colour) to the
  /// standard frame, or null if the two colours aren't a valid adjacent pair.
  static _Rot? _rotationFor(CubeColour top, CubeColour front) {
    final topFace = _colourFace[top];
    final frontFace = _colourFace[front];
    if (topFace == null || frontFace == null) return null;
    for (final r in _rotations) {
      if (_centreFace[r.apply(_faceCentre[topFace]!)] == 'U' &&
          _centreFace[r.apply(_faceCentre[frontFace]!)] == 'F') {
        return r;
      }
    }
    return null;
  }

  /// True when (top, front) is a valid orientation (adjacent, distinct faces).
  static bool isValid(CubeColour top, CubeColour front) =>
      _rotationFor(top, front) != null;

  /// The 4 front colours available for a chosen top (its adjacent faces).
  static List<CubeColour> frontsFor(CubeColour top) =>
      [for (final c in CubeColour.values) if (isValid(top, c)) c];

  /// All 24 valid (top, front) holding orientations.
  static List<(CubeColour, CubeColour)> allOrientations() => [
        for (final top in CubeColour.values)
          for (final front in frontsFor(top)) (top, front),
      ];

  /// Rotate [facelets] from the user's (top, front) holding frame into the
  /// standard frame. Identity for white/green; returns the input unchanged if
  /// the pair is invalid.
  static String normaliseFacelets(String facelets,
      {required CubeColour top, required CubeColour front}) {
    final rot = _rotationFor(top, front);
    if (rot == null || facelets.length != 54) return facelets;
    return _apply(facelets, rot);
  }

  static String _apply(String facelets, _Rot rot) {
    final relabel = {
      for (final f in _faces) f: _centreFace[rot.apply(_faceCentre[f]!)]!,
    };
    final out = List<String>.filled(54, '');
    for (var i = 0; i < 54; i++) {
      final j = _indexAt[(rot.apply(_pos[i]), rot.apply(_normal[i]))]!;
      out[j] = relabel[facelets[i]]!;
    }
    return out.join();
  }

  /// The face letter a cube-reported [face] reads as in the user's holding
  /// frame: the cube names the face it turned in its own frame, so held
  /// white-top/red-front its F (green) is the user's L. Same relabelling as
  /// [normaliseFacelets], so moves and states agree.
  static String normaliseFace(String face,
      {required CubeColour top, required CubeColour front}) {
    final rot = _rotationFor(top, front);
    final centre = _faceCentre[face];
    if (rot == null || centre == null) return face;
    return _centreFace[rot.apply(centre)]!;
  }

  /// Inverse of [normaliseFacelets] (standard → user frame). Exposed for tests
  /// and the future 3D view.
  static String denormaliseFacelets(String facelets,
      {required CubeColour top, required CubeColour front}) {
    final rot = _rotationFor(top, front);
    if (rot == null || facelets.length != 54) return facelets;
    return _apply(facelets, rot.inverse());
  }
}

typedef _Vec = (int, int, int);

// A cube rotation as the images of the x/y/z unit vectors (signed perm matrix).
class _Rot {
  final _Vec ex, ey, ez;
  const _Rot(this.ex, this.ey, this.ez);

  _Vec apply(_Vec c) => (
        c.$1 * ex.$1 + c.$2 * ey.$1 + c.$3 * ez.$1,
        c.$1 * ex.$2 + c.$2 * ey.$2 + c.$3 * ez.$2,
        c.$1 * ex.$3 + c.$2 * ey.$3 + c.$3 * ez.$3,
      );

  _Rot then(_Rot o) => _Rot(o.apply(ex), o.apply(ey), o.apply(ez));

  _Rot inverse() {
    // Transpose of a signed permutation matrix is its inverse.
    return _Rot(
      (ex.$1, ey.$1, ez.$1),
      (ex.$2, ey.$2, ez.$2),
      (ex.$3, ey.$3, ez.$3),
    );
  }

  @override
  bool operator ==(Object o) =>
      o is _Rot && o.ex == ex && o.ey == ey && o.ez == ez;

  @override
  int get hashCode => Object.hash(ex, ey, ez);
}
