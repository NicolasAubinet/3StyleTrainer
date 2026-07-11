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
    final out = List<String>.from(startFacelets.split(''));
    for (final (src, dst) in cyc) {
      out[dst] = startFacelets[src];
    }
    return out.join();
  }

  /// Is the cube (in [currentFacelets]) at the expected state for [pair]?
  static bool isPairComplete(
      String currentFacelets, String startFacelets, String pair, AlgType algType) {
    final expected = expectedAfterPair(startFacelets, pair, algType);
    return expected != null && expected == currentFacelets;
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

  /// The facelet-move list (source → destination) for a pair's 3-cycle, or
  /// `null` if unsupported. Corners/edges only for now.
  static List<(int, int)>? _cycle(String pair, AlgType algType) {
    final isCorner = algType == AlgType.Corner;
    final isEdge = algType == AlgType.Edge;
    if (!isCorner && !isEdge) return null;

    final resolved = _resolvePositions(pair, algType, isEdge);
    if (resolved == null) return null;
    final (bufferPrimary, xi, yi) = resolved;

    final stickers = isCorner ? _cornerStickers : _edgeStickers;
    final pieceFacelets = isCorner ? CubieCube.cFacelet : CubieCube.eFacelet;
    final perPiece = isCorner ? 3 : 2;

    final b = stickers[bufferPrimary];
    final x = stickers[xi];
    final y = stickers[yi];
    if (b == null || x == null || y == null) return null;

    // Rigid 3-cycle of the buffer, X and Y pieces (buffer→X→Y→buffer), aligning
    // the buffer's reference sticker onto X's, X's onto Y's, Y's onto buffer's.
    final moves = <(int, int)>[];
    for (var k = 0; k < perPiece; k++) {
      final fb = pieceFacelets[b.piece][(b.pos + k) % perPiece];
      final fx = pieceFacelets[x.piece][(x.pos + k) % perPiece];
      final fy = pieceFacelets[y.piece][(y.pos + k) % perPiece];
      moves.add((fb, fx)); // buffer sticker → X slot
      moves.add((fx, fy)); // X sticker → Y slot
      moves.add((fy, fb)); // Y sticker → buffer slot
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
