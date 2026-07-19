/// A 3D-coordinate facelet cube, used only to VERIFY the §31a algebra
/// end-to-end. Stickers live at (cubie position, outward normal); a turn
/// rotates every sticker whose coordinate along an axis matches a layer.
///
/// Face normals: U=+y D=-y L=-x R=+x F=+z B=-z.
/// A clockwise turn (looking at the face from outside) is a -90 deg rotation
/// about the outward normal under the right-hand rule.

import 'algebra.dart';

typedef Vec = List<int>;

const List<Vec> faceNormals = [
  [0, 1, 0], // U
  [0, -1, 0], // D
  [-1, 0, 0], // L
  [1, 0, 0], // R
  [0, 0, 1], // F
  [0, 0, -1], // B
];

/// Right-hand-rule rotation of [v] about [axis] by -90 degrees (clockwise seen
/// from the tip of [axis]).
Vec rotateNeg90(Vec v, Vec axis) {
  final x = v[0], y = v[1], z = v[2];
  if (axis[0] != 0) {
    final s = axis[0]; // +/-1
    // about +x by -90: (x, y, z) -> (x, z, -y)
    return s > 0 ? [x, z, -y] : [x, -z, y];
  }
  if (axis[1] != 0) {
    final s = axis[1];
    // about +y by -90: (x, y, z) -> (-z, y, x)
    return s > 0 ? [-z, y, x] : [z, y, -x];
  }
  final s = axis[2];
  // about +z by -90: (x, y, z) -> (y, -x, z)
  return s > 0 ? [y, -x, z] : [-y, x, z];
}

Vec rotateBy(Vec v, Vec axis, int amount) {
  var r = v;
  for (var i = 0; i < amount; i++) {
    r = rotateNeg90(r, axis);
  }
  return r;
}

int dotAxis(Vec pos, Vec axis) =>
    pos[0] * axis[0] + pos[1] * axis[1] + pos[2] * axis[2];

String slotKey(Vec pos, Vec normal) =>
    '${pos[0]},${pos[1]},${pos[2]}|${normal[0]},${normal[1]},${normal[2]}';

class CubeState {
  /// slot key -> colour (face index)
  final Map<String, int> stickers;
  CubeState(this.stickers);

  static CubeState solved() {
    final m = <String, int>{};
    for (var x = -1; x <= 1; x++) {
      for (var y = -1; y <= 1; y++) {
        for (var z = -1; z <= 1; z++) {
          for (var f = 0; f < 6; f++) {
            final n = faceNormals[f];
            if (dotAxis([x, y, z], n) == 1) {
              m[slotKey([x, y, z], n)] = f;
            }
          }
        }
      }
    }
    return CubeState(m);
  }

  CubeState copy() => CubeState(Map<String, int>.from(stickers));

  /// Rotate the layers whose coordinate along [axis] is in [layers], by
  /// [amount] quarter turns clockwise about [axis].
  CubeState turn(Vec axis, List<int> layers, int amount) {
    final out = <String, int>{};
    stickers.forEach((key, colour) {
      final parts = key.split('|');
      final p = parts[0].split(',').map(int.parse).toList();
      final n = parts[1].split(',').map(int.parse).toList();
      if (layers.contains(dotAxis(p, axis))) {
        out[slotKey(rotateBy(p, axis, amount), rotateBy(n, axis, amount))] = colour;
      } else {
        out[key] = colour;
      }
    });
    return CubeState(out);
  }

  /// Whole-cube rotation given as a face permutation (one of the 24).
  CubeState applyOrientation(List<int> perm) {
    // Find the axis/amount combination matching perm by search over the group
    // generators; simplest is to rebuild the sticker map directly using the
    // face permutation on both position and normal.
    final out = <String, int>{};
    stickers.forEach((key, colour) {
      final parts = key.split('|');
      final p = parts[0].split(',').map(int.parse).toList();
      final n = parts[1].split(',').map(int.parse).toList();
      out[slotKey(_mapVec(p, perm), _mapVec(n, perm))] = colour;
    });
    return CubeState(out);
  }

  /// Map a vector through a face permutation: decompose into face-axis
  /// components and send each to its image.
  static Vec _mapVec(Vec v, List<int> perm) {
    var acc = [0, 0, 0];
    for (var f = 0; f < 6; f++) {
      final n = faceNormals[f];
      final c = dotAxis(v, n);
      if (c != 0) {
        final img = faceNormals[perm[f]];
        acc = [acc[0] + c * img[0], acc[1] + c * img[1], acc[2] + c * img[2]];
      }
    }
    // Each of the 3 axes contributes twice (f and its opposite), so halve.
    return [acc[0] ~/ 2, acc[1] ~/ 2, acc[2] ~/ 2];
  }

  @override
  bool operator ==(Object other) {
    if (other is! CubeState) return false;
    if (other.stickers.length != stickers.length) return false;
    for (final e in stickers.entries) {
      if (other.stickers[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => stickers.length;
}

/// Apply a solver-frame move directly (room frame).
CubeState applySolverMove(CubeState s, Move m) {
  switch (m.kind) {
    case MoveKind.outer:
      return s.turn(faceNormals[m.id], [1], m.amount);
    case MoveKind.wide:
      return s.turn(faceNormals[m.id], [1, 0], m.amount);
    case MoveKind.rotation:
      // x follows R, y follows U, z follows F.
      final n = faceNormals[[R, U, F][m.id]];
      return s.turn(n, [1, 0, -1], m.amount);
    case MoveKind.slice:
      // M follows L, E follows D, S follows F.
      final n = faceNormals[[L, D, F][m.id]];
      return s.turn(n, [0], m.amount);
  }
}

CubeState applySolverAlg(CubeState s, List<Move> alg) {
  var cur = s;
  for (final m in alg) {
    cur = applySolverMove(cur, m);
  }
  return cur;
}
