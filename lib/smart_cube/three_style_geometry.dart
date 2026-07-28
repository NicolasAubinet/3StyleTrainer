import 'package:smartcube/smartcube.dart';

import '../alg_provider.dart';
import '../alg_structs.dart';
import '../audio_edge_scheme.dart';

/// Bridges the app's SpeFFz sticker lettering to physical cube facelets (the
/// [CubieCube] 54-facelet model the smart cube reports in), and computes, for a
/// shown letter pair, the **expected cube state** after the case is executed —
/// the signal the timer uses to detect completion.
///
/// A letter pair "XY" performs a 3-cycle of the buffer piece and the pieces
/// owning stickers X and Y. Executing it from a start state `S` yields
/// `Δ_pair ∘ S`; the case is complete when the cube reaches that state.
///
/// Everything works in *physical* space, so it is scheme-agnostic: a custom
/// lettering (e.g. the audio edges) only needs its own sticker→facelet map.
class ThreeStyleGeometry {
  // SpeFFz corner sticker triples with the matching CubieCube corner index
  // (0=URF,1=UFL,2=ULB,3=UBR,4=DFR,5=DLF,6=DBL,7=DRB), derived from the app's
  // own buffer / colliding-group definitions.
  static const List<(List<int>, int)> _cornerGroups = [
    ([2, 9, 12], 0), // UFR
    ([3, 5, 8], 1), // UFL
    ([0, 4, 17], 2), // UBL
    ([1, 13, 16], 3), // UBR
    ([21, 10, 15], 4), // DFR
    ([20, 6, 11], 5), // DFL
    ([23, 7, 18], 6), // DBL
    ([22, 14, 19], 7), // DBR
  ];

  static const List<(List<int>, int)> _edgeGroups = [
    ([2, 8], 1), // UF
    ([0, 16], 3), // UB
    ([1, 12], 0), // UR
    ([3, 4], 2), // UL
    ([9, 15], 8), // FR
    ([11, 5], 9), // FL
    ([20, 10], 5), // DF
    ([22, 18], 7), // DB
    ([21, 14], 4), // DR
    ([23, 6], 6), // DL
    ([7, 17], 10), // BL
    ([13, 19], 11), // BR
  ];

  // SpeFFz face (index ~/ 4: U,L,F,R,B,D) → CubieCube face (U,R,F,D,L,B).
  static const List<int> _speffzFaceToCubeFace = [0, 4, 2, 1, 5, 3];

  // Edge name (as in LetterPairScheme.Flips) → CubieCube edge piece.
  static const Map<String, int> _edgePieceByName = {
    'UR': 0, 'UF': 1, 'UL': 2, 'UB': 3, 'DR': 4, 'DF': 5,
    'DL': 6, 'DB': 7, 'FR': 8, 'FL': 9, 'BL': 10, 'BR': 11,
  };

  // Corner buffer piece → its two same-face edges (the parity swap candidates).
  static const Map<int, List<int>> _cornerBufferEdges = {
    0: [1, 0], // URF → UF, UR
    1: [1, 2], // UFL → UF, UL
    3: [3, 0], // UBR → UB, UR
    2: [2, 3], // ULB → UL, UB
    4: [5, 4], // DFR → DF, DR
    5: [6, 5], // DLF → DL, DF
  };

  // Every corner facelet, for parity's exact corner comparison.
  static final List<int> _allCornerFacelets = [
    for (final f in CubieCube.cFacelet) ...f,
  ];

  // Per-sticker resolved geometry, built once.
  static final Map<int, _Sticker> _cornerStickers = _buildStickers(
      _cornerGroups, CubieCube.cFacelet, 3);
  static final Map<int, _Sticker> _edgeStickers = _buildStickers(
      _edgeGroups, CubieCube.eFacelet, 2);

  static Map<int, _Sticker> _buildStickers(
      List<(List<int>, int)> groups, List<List<int>> pieceFacelets, int perPiece) {
    final out = <int, _Sticker>{};
    for (final (stickers, piece) in groups) {
      for (final s in stickers) {
        final cubeFace = _speffzFaceToCubeFace[s ~/ 4];
        final facelet =
            pieceFacelets[piece].firstWhere((f) => f ~/ 9 == cubeFace);
        final pos = pieceFacelets[piece].indexOf(facelet);
        out[s] = _Sticker(facelet: facelet, piece: piece, pos: pos);
      }
    }
    return out;
  }

  /// The 54-char facelet string expected once the [pair] is executed from
  /// [startFacelets]. Returns `null` if the pair can't be mapped (e.g. an
  /// unsupported alg type or unknown letters).
  static String? expectedAfterPair(
      String startFacelets, String pair, AlgType algType) {
    final cyc = _cycle(pair, algType);
    if (cyc == null) return null;
    return _apply(startFacelets, cyc);
  }

  static String _apply(String startFacelets, List<(int, int)> moves) {
    final out = List<String>.from(startFacelets.split(''));
    for (final (src, dst) in moves) {
      out[dst] = startFacelets[src];
    }
    return out.join();
  }

  /// Is the cube (in [currentFacelets]) at the expected state for [pair]?
  static bool isPairComplete(
      String currentFacelets, String startFacelets, String pair, AlgType algType) {
    if (algType == AlgType.Parity) {
      return _parityComplete(currentFacelets, startFacelets, pair);
    }
    final expected = expectedAfterPair(startFacelets, pair, algType);
    return expected != null && expected == currentFacelets;
  }

  /// The alg type whose geometry maps *every* pair in [pairs] — used to drive a
  /// custom set cube-side when its pairs are actually a known scheme. Tries the
  /// types in order (corner-first tie-break: a two-letter SpeFFz pair is valid
  /// as both corner and edge). Returns `null` for an empty set or when no single
  /// type maps all pairs.
  static AlgType? detectAlgType(Iterable<String> pairs) {
    final list = pairs.toList();
    if (list.isEmpty) return null;
    for (final type in const [
      AlgType.Corner,
      AlgType.Edge,
      AlgType.TwoFlip,
      AlgType.TwoTwist,
      AlgType.Parity,
    ]) {
      final ok = list.every(
          (p) => expectedAfterPair(CubeState.solvedFacelets, p, type) != null);
      if (ok) return type;
    }
    return null;
  }

  /// If the settled cube matches a *different* pair than the one shown, return
  /// that pair (for "you executed BA instead of AB" feedback); else `null`.
  static String? matchingPair(String currentFacelets, String startFacelets,
      AlgType algType, Iterable<String> candidatePairs) {
    for (final p in candidatePairs) {
      if (isPairComplete(currentFacelets, startFacelets, p, algType)) return p;
    }
    return null;
  }

  /// The pair — other than [shown] — that the settled cube matches from any of
  /// [baselines] (oldest first), mirroring completion so a pause mid-alg can't
  /// hide a wrong alg. Completing [shown] wins: 3-cycles compose, so a correct
  /// solve is also another case measured from an earlier rest.
  static String? executedOtherPair(String currentFacelets,
      List<String> baselines, AlgType algType, Iterable<String> candidatePairs,
      {required String shown}) {
    for (final b in baselines) {
      if (isPairComplete(currentFacelets, b, shown, algType)) return null;
    }
    for (final b in baselines) {
      final p = matchingPair(currentFacelets, b, algType, candidatePairs);
      if (p != null && p != shown) return p;
    }
    return null;
  }

  /// The facelet-move list (source → destination) for a case, or `null` if the
  /// pair can't be mapped under [algType].
  static List<(int, int)>? _cycle(String pair, AlgType algType) {
    switch (algType) {
      case AlgType.Corner:
      case AlgType.Edge:
        return _threeCycle(pair, algType);
      case AlgType.TwoFlip:
        return _twoFlip(pair);
      case AlgType.TwoTwist:
        return _twoTwist(pair);
      case AlgType.Parity:
        return _parity(pair);
      case AlgType.Custom:
        return null;
    }
  }

  // Corner/edge 3-cycle: buffer→X→Y→buffer, aligning each piece's reference
  // sticker onto the next (the buffer's onto X's, X's onto Y's, Y's onto the
  // buffer's).
  static List<(int, int)>? _threeCycle(String pair, AlgType algType) {
    final isEdge = algType == AlgType.Edge;
    final resolved = _resolvePositions(pair, algType, isEdge);
    if (resolved == null) return null;
    final (bufferPrimary, xi, yi) = resolved;

    final stickers = isEdge ? _edgeStickers : _cornerStickers;
    final pieceFacelets = isEdge ? CubieCube.eFacelet : CubieCube.cFacelet;
    final perPiece = isEdge ? 2 : 3;

    final b = stickers[bufferPrimary];
    final x = stickers[xi];
    final y = stickers[yi];
    if (b == null || x == null || y == null) return null;

    return _rigidCycle([(b.piece, b.pos), (x.piece, x.pos), (y.piece, y.pos)],
        pieceFacelets, perPiece);
  }

  // 2-flip "X-Y": flip edges X and Y in place — swap each edge's two facelets.
  static List<(int, int)>? _twoFlip(String pair) {
    final parts = pair.split('-');
    if (parts.length != 2) return null;
    final moves = <(int, int)>[];
    for (final name in parts) {
      final piece = _edgePieceByName[name];
      if (piece == null) return null;
      final f = CubieCube.eFacelet[piece];
      moves.add((f[0], f[1]));
      moves.add((f[1], f[0]));
    }
    return moves;
  }

  // 2-twist "X-Y": twist the two named corners in place in opposite directions
  // (the enumerator guarantees the orientations sum to 0 mod 3). Twisting a
  // corner cyclically shifts its three facelets by its twist orientation.
  static List<(int, int)>? _twoTwist(String pair) {
    final parts = pair.split('-');
    if (parts.length != 2) return null;
    final scheme = getAlgSets(AlgType.TwoTwist);
    final moves = <(int, int)>[];
    for (final letter in parts) {
      final idx = scheme.indexOf(letter);
      if (idx < 0) return null;
      final ori = cornerTwistOrientation(idx);
      final st = _cornerStickers[idx];
      if (ori == null || st == null) return null;
      final f = CubieCube.cFacelet[st.piece];
      for (var k = 0; k < 3; k++) {
        moves.add((f[k], f[(k + ori) % 3]));
      }
    }
    return moves;
  }

  // Parity "L": swap the buffer corner with the corner owning sticker L, plus a
  // swap of two edges. Which two is the solver's choice and can even differ per
  // alg, so the expected state carries the corner buffer's own same-face edges
  // as a representative and completion takes any rigid swap (_parityComplete).
  static List<(int, int)>? _parity(String pair) {
    final corners = _parityCornerSwap(pair);
    final buffer = _cornerStickers[getBufferIndices(AlgType.Parity).first];
    final edges = buffer == null ? null : _cornerBufferEdges[buffer.piece];
    if (corners == null || edges == null) return null;
    return [
      ...corners,
      ..._rigidCycle([(edges[0], 0), (edges[1], 0)], CubieCube.eFacelet, 2),
    ];
  }

  static List<(int, int)>? _parityCornerSwap(String pair) {
    final li = getAlgSets(AlgType.Parity).indexOf(pair);
    if (li < 0) return null;
    final target = _cornerStickers[li];
    final buffer = _cornerStickers[getBufferIndices(AlgType.Parity).first];
    if (target == null || buffer == null) return null;
    return _rigidCycle([(buffer.piece, buffer.pos), (target.piece, target.pos)],
        CubieCube.cFacelet, 3);
  }

  // Parity completes on its corner swap plus a rigid swap of *any* two edges:
  // solvers pick their own parity edge swap, and it can differ per alg. The
  // corners are checked whole, so only which *edges* moved is left open — and
  // landing the two of them flipped is still an error.
  static bool _parityComplete(String current, String start, String pair) {
    final corners = _parityCornerSwap(pair);
    if (corners == null) return false;
    final expected = _apply(start, corners);
    for (final f in _allCornerFacelets) {
      if (current[f] != expected[f]) return false;
    }
    return _isOneRigidEdgeSwap(current, start);
  }

  static bool _isOneRigidEdgeSwap(String current, String start) {
    int a = -1, b = -1;
    for (var e = 0; e < CubieCube.eFacelet.length; e++) {
      final f = CubieCube.eFacelet[e];
      if (current[f[0]] == start[f[0]] && current[f[1]] == start[f[1]]) continue;
      if (a < 0) {
        a = e;
      } else if (b < 0) {
        b = e;
      } else {
        return false; // more than two edges moved
      }
    }
    if (b < 0) return false;
    final fa = CubieCube.eFacelet[a];
    final fb = CubieCube.eFacelet[b];
    for (var k = 0; k < 2; k++) {
      if (current[fa[k]] != start[fb[k]] || current[fb[k]] != start[fa[k]]) {
        return false; // swapped, but flipped
      }
    }
    return true;
  }

  // Rigid cycle of pieces ring[0]→ring[1]→…→ring[0]; each (piece, pos) gives the
  // reference-sticker offset to align. Emits (src, dst) facelet moves — the
  // sticker at src lands on dst.
  static List<(int, int)> _rigidCycle(
      List<(int, int)> ring, List<List<int>> pieceFacelets, int perPiece) {
    final moves = <(int, int)>[];
    for (var k = 0; k < perPiece; k++) {
      for (var i = 0; i < ring.length; i++) {
        final (p0, pos0) = ring[i];
        final (p1, pos1) = ring[(i + 1) % ring.length];
        moves.add((pieceFacelets[p0][(pos0 + k) % perPiece],
            pieceFacelets[p1][(pos1 + k) % perPiece]));
      }
    }
    return moves;
  }

  // Pair name -> SpeFFz position indices (buffer, X, Y). Audio edges route
  // through AudioEdgeScheme; everything else already speaks SpeFFz.
  static (int, int, int)? _resolvePositions(
      String pair, AlgType algType, bool isEdge) {
    if (isEdge && USE_EDGE_AUDIO_SYLLABLES) {
      final xy = AudioEdgeScheme.parseToSpeffz(pair);
      if (xy == null) return null;
      return (AudioEdgeScheme.bufferSpeffz, xy.$1, xy.$2);
    }
    final scheme = getAlgSets(algType);
    final letters = pair.split('');
    if (letters.length != 2) return null;
    final xi = scheme.indexOf(letters[0]);
    final yi = scheme.indexOf(letters[1]);
    if (xi < 0 || yi < 0) return null;
    return (getBufferIndices(algType).first, xi, yi);
  }
}

class _Sticker {
  final int facelet;
  final int piece;
  final int pos;
  const _Sticker({required this.facelet, required this.piece, required this.pos});
}
