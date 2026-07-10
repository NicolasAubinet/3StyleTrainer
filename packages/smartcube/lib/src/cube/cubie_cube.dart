import '../model/cube_move.dart';

/// Cube state in the classic corner/edge permutation+orientation model, ported
/// to Dart from csTimer's `mathlib.CubieCube` (cs0x7f/cstimer, GPL-3.0).
///
/// - [ca] — 8 corners. Each entry packs permutation in bits 0–2 (`& 7`, which
///   corner sits here) and orientation in bits 3–4 (`>> 3`, 0–2 twist).
/// - [ea] — 12 edges. Permutation in bits 1–11 (`>> 1`), orientation in bit 0
///   (`& 1`, flip).
///
/// Whole-cube reorientation (`ori`) is intentionally omitted: move tracking
/// never rotates the model (the gyro stream handles physical orientation), so
/// it stays 0 and the orientation branches of the original are unnecessary.
class CubieCube {
  /// Solved-cube facelet string, faces in URFDLB order (9 stickers each).
  static const String solvedFacelet =
      'UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB';

  final List<int> ca;
  final List<int> ea;

  CubieCube()
      : ca = [0, 1, 2, 3, 4, 5, 6, 7],
        ea = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22];

  CubieCube.from(List<int> ca, List<int> ea)
      : ca = ca.sublist(0, 8),
        ea = ea.sublist(0, 12);

  CubieCube clone() => CubieCube.from(ca, ea);

  void init(List<int> ca, List<int> ea) {
    for (var i = 0; i < 8; i++) {
      this.ca[i] = ca[i];
    }
    for (var i = 0; i < 12; i++) {
      this.ea[i] = ea[i];
    }
  }

  static void cornMult(CubieCube a, CubieCube b, CubieCube prod) {
    for (var corn = 0; corn < 8; corn++) {
      final ori = ((a.ca[b.ca[corn] & 7] >> 3) + (b.ca[corn] >> 3)) % 3;
      prod.ca[corn] = a.ca[b.ca[corn] & 7] & 7 | ori << 3;
    }
  }

  static void edgeMult(CubieCube a, CubieCube b, CubieCube prod) {
    for (var ed = 0; ed < 12; ed++) {
      prod.ea[ed] = a.ea[b.ea[ed] >> 1] ^ (b.ea[ed] & 1);
    }
  }

  static void cubeMult(CubieCube a, CubieCube b, CubieCube prod) {
    cornMult(a, b, prod);
    edgeMult(a, b, prod);
  }

  /// Corner facelet indices, one triple per corner (URF, UFL, …).
  static const List<List<int>> cFacelet = [
    [8, 9, 20], // URF
    [6, 18, 38], // UFL
    [0, 36, 47], // ULB
    [2, 45, 11], // UBR
    [29, 26, 15], // DFR
    [27, 44, 24], // DLF
    [33, 53, 42], // DBL
    [35, 17, 51], // DRB
  ];

  /// Edge facelet indices, one pair per edge (UR, UF, …).
  static const List<List<int>> eFacelet = [
    [5, 10], // UR
    [7, 19], // UF
    [3, 37], // UL
    [1, 46], // UB
    [32, 16], // DR
    [28, 25], // DF
    [30, 43], // DL
    [34, 52], // DB
    [23, 12], // FR
    [21, 41], // FL
    [50, 39], // BL
    [48, 14], // BR
  ];

  List<int> _toPerm() {
    final f = List<int>.generate(54, (i) => i);
    for (var c = 0; c < 8; c++) {
      final j = ca[c] & 0x7;
      final ori = ca[c] >> 3;
      for (var n = 0; n < 3; n++) {
        f[cFacelet[c][(n + ori) % 3]] = cFacelet[j][n];
      }
    }
    for (var e = 0; e < 12; e++) {
      final j = ea[e] >> 1;
      final ori = ea[e] & 1;
      for (var n = 0; n < 2; n++) {
        f[eFacelet[e][(n + ori) % 2]] = eFacelet[j][n];
      }
    }
    return f;
  }

  /// The 54-character facelet string for this state (URFDLB face order).
  String toFaceCube() {
    const ts = 'URFDLB';
    final perm = _toPerm();
    final f = List<String>.filled(54, '');
    for (var i = 0; i < 54; i++) {
      f[i] = ts[perm[i] ~/ 9];
    }
    return f.join();
  }

  /// Parse a 54-character facelet string into this cube. Returns `false` if the
  /// facelets are structurally invalid (wrong colour counts / no matching piece).
  bool fromFacelet(String facelet) {
    if (facelet.length != 54) return false;
    final centers = facelet[4] +
        facelet[13] +
        facelet[22] +
        facelet[31] +
        facelet[40] +
        facelet[49];
    final f = List<int>.filled(54, 0);
    var count = 0;
    for (var i = 0; i < 54; i++) {
      final c = centers.indexOf(facelet[i]);
      if (c == -1) return false;
      f[i] = c;
      count += 1 << (c << 2);
    }
    if (count != 0x999999) return false;

    for (var i = 0; i < 8; i++) {
      var ori = 0;
      for (; ori < 3; ori++) {
        if (f[cFacelet[i][ori]] == 0 || f[cFacelet[i][ori]] == 3) break;
      }
      final col1 = f[cFacelet[i][(ori + 1) % 3]];
      final col2 = f[cFacelet[i][(ori + 2) % 3]];
      for (var j = 0; j < 8; j++) {
        if (col1 == cFacelet[j][1] ~/ 9 && col2 == cFacelet[j][2] ~/ 9) {
          ca[i] = j | (ori % 3) << 3;
          break;
        }
      }
    }
    for (var i = 0; i < 12; i++) {
      for (var j = 0; j < 12; j++) {
        if (f[eFacelet[i][0]] == eFacelet[j][0] ~/ 9 &&
            f[eFacelet[i][1]] == eFacelet[j][1] ~/ 9) {
          ea[i] = j << 1;
          break;
        }
        if (f[eFacelet[i][0]] == eFacelet[j][1] ~/ 9 &&
            f[eFacelet[i][1]] == eFacelet[j][0] ~/ 9) {
          ea[i] = j << 1 | 1;
          break;
        }
      }
    }
    return true;
  }

  /// Apply a single quarter turn in place.
  void applyMove(Face face, bool prime) {
    final tmp = CubieCube();
    cubeMult(this, moveCube[moveIndex(face, prime)], tmp);
    init(tmp.ca, tmp.ea);
  }

  bool get isSolved {
    for (var i = 0; i < 8; i++) {
      if (ca[i] != i) return false;
    }
    for (var i = 0; i < 12; i++) {
      if (ea[i] != i << 1) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (other is! CubieCube) return false;
    for (var i = 0; i < 8; i++) {
      if (ca[i] != other.ca[i]) return false;
    }
    for (var i = 0; i < 12; i++) {
      if (ea[i] != other.ea[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var ret = 0;
    for (var i = 0; i < 20; i++) {
      ret = 0xffffffff & (ret * 31 + (i < 12 ? ea[i] : ca[i - 12]));
    }
    return ret;
  }

  /// Face order used by [moveCube] indices: U R F D L B.
  static const List<Face> _moveFaceOrder = [
    Face.U,
    Face.R,
    Face.F,
    Face.D,
    Face.L,
    Face.B,
  ];

  /// Index into [moveCube] for a quarter turn (power 0 = CW, 2 = CCW/prime).
  static int moveIndex(Face face, bool prime) =>
      _moveFaceOrder.indexOf(face) * 3 + (prime ? 2 : 0);

  /// The 18 basic moves (6 faces × {CW, 180°, CCW}) as cube states.
  static final List<CubieCube> moveCube = _buildMoveCube();

  static List<CubieCube> _buildMoveCube() {
    final mc = List<CubieCube>.generate(18, (_) => CubieCube());
    mc[0].init([3, 0, 1, 2, 4, 5, 6, 7],
        [6, 0, 2, 4, 8, 10, 12, 14, 16, 18, 20, 22]); // U
    mc[3].init([20, 1, 2, 8, 15, 5, 6, 19],
        [16, 2, 4, 6, 22, 10, 12, 14, 8, 18, 20, 0]); // R
    mc[6].init([9, 21, 2, 3, 16, 12, 6, 7],
        [0, 19, 4, 6, 8, 17, 12, 14, 3, 11, 20, 22]); // F
    mc[9].init([0, 1, 2, 3, 5, 6, 7, 4],
        [0, 2, 4, 6, 10, 12, 14, 8, 16, 18, 20, 22]); // D
    mc[12].init([0, 10, 22, 3, 4, 17, 13, 7],
        [0, 2, 20, 6, 8, 10, 18, 14, 16, 4, 12, 22]); // L
    mc[15].init([0, 1, 11, 23, 4, 5, 18, 14],
        [0, 2, 4, 23, 8, 10, 12, 21, 16, 18, 7, 15]); // B
    for (var a = 0; a < 18; a += 3) {
      for (var p = 0; p < 2; p++) {
        cubeMult(mc[a + p], mc[a], mc[a + p + 1]);
      }
    }
    return mc;
  }
}
