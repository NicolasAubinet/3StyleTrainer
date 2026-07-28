import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/smart_cube/three_style_geometry.dart';

const solved = CubieCube.solvedFacelet;

// Which facelets belong to the 3 corners of a pair, for the default UFR buffer.
Set<int> _cornerFacelets(List<int> pieces) => {
      for (final p in pieces) ...CubieCube.cFacelet[p],
    };

void main() {
  group('corners (default SpeFFz scheme, UFR buffer)', () {
    // "AD": A on UBL (cube corner 2), D on UFL (cube corner 1); buffer UFR (0).
    const pair = 'AD';

    test('expected state is a valid cube', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Corner)!;
      expect(exp.length, 54);
      expect(CubieCube().fromFacelet(exp), isTrue,
          reason: 'a real 3-cycle must be a legal cube state');
    });

    test('only the three involved corners change', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Corner)!;
      final involved = _cornerFacelets([0, 1, 2]); // UFR, UFL, UBL
      for (var i = 0; i < 54; i++) {
        if (!involved.contains(i)) {
          expect(exp[i], solved[i], reason: 'facelet $i outside the cycle moved');
        }
      }
    });

    test('it is a genuine 3-cycle (order 3)', () {
      var s = solved;
      for (var i = 0; i < 3; i++) {
        s = ThreeStyleGeometry.expectedAfterPair(s, pair, AlgType.Corner)!;
      }
      expect(s, solved, reason: 'applying the case three times returns to solved');
    });

    test('AD and DA are inverses', () {
      final ad = ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!;
      final back = ThreeStyleGeometry.expectedAfterPair(ad, 'DA', AlgType.Corner)!;
      expect(back, solved);
    });

    test('isPairComplete: true at the expected state, false at the start', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Corner)!;
      expect(
          ThreeStyleGeometry.isPairComplete(exp, solved, pair, AlgType.Corner),
          isTrue);
      expect(
          ThreeStyleGeometry.isPairComplete(solved, solved, pair, AlgType.Corner),
          isFalse);
    });

    test('matchingPair distinguishes AD from DA (wrong-case detection)', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!;
      final match = ThreeStyleGeometry.matchingPair(
          exp, solved, AlgType.Corner, ['AB', 'DA', 'AD', 'BC']);
      expect(match, 'AD');
    });

    test('works from an already-scrambled start state', () {
      // Do one case, then a second from the resulting (non-solved) state.
      final s1 = ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!;
      expect(s1 == solved, isFalse);
      final s2 = ThreeStyleGeometry.expectedAfterPair(s1, 'BW', AlgType.Corner)!;
      expect(CubieCube().fromFacelet(s2), isTrue);
      expect(ThreeStyleGeometry.isPairComplete(s2, s1, 'BW', AlgType.Corner),
          isTrue);
    });
  });

  group('edges (default SpeFFz scheme, UF buffer)', () {
    const pair = 'AB'; // A on UB, B on UR; buffer UF.

    test('expected state is a valid cube and a 3-cycle', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Edge)!;
      expect(CubieCube().fromFacelet(exp), isTrue);
      var s = solved;
      for (var i = 0; i < 3; i++) {
        s = ThreeStyleGeometry.expectedAfterPair(s, pair, AlgType.Edge)!;
      }
      expect(s, solved);
    });

    test('AB and BA are inverses', () {
      final ab = ThreeStyleGeometry.expectedAfterPair(solved, 'AB', AlgType.Edge)!;
      final back = ThreeStyleGeometry.expectedAfterPair(ab, 'BA', AlgType.Edge)!;
      expect(back, solved);
    });

    test('completion detection', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Edge)!;
      expect(ThreeStyleGeometry.isPairComplete(exp, solved, pair, AlgType.Edge),
          isTrue);
    });
  }, skip: USE_EDGE_AUDIO_SYLLABLES ? 'SpeFFz edges: audio flag is on' : false);

  // Only meaningful when the audio-syllable edge scheme is active; the geometry
  // routes audio pairs through AudioEdgeScheme into SpeFFz space.
  group('edges (audio syllable scheme)', () {
    const pair = 'be'; // consonant b (UL) + vowel e (UB); buffer UF.

    test('expected state is a valid cube and a genuine 3-cycle', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Edge)!;
      expect(CubieCube().fromFacelet(exp), isTrue);
      var s = solved;
      for (var i = 0; i < 3; i++) {
        s = ThreeStyleGeometry.expectedAfterPair(s, pair, AlgType.Edge)!;
      }
      expect(s, solved, reason: 'applying the case three times returns to solved');
    });

    test('a pair and its reverse are inverses', () {
      // "be" = buffer->UL->UB; its reverse is "ca" = buffer->UB->UL.
      final be = ThreeStyleGeometry.expectedAfterPair(solved, 'be', AlgType.Edge)!;
      final back = ThreeStyleGeometry.expectedAfterPair(be, 'ca', AlgType.Edge)!;
      expect(back, solved);
    });

    test('completion detection', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Edge)!;
      expect(ThreeStyleGeometry.isPairComplete(exp, solved, pair, AlgType.Edge),
          isTrue);
    });

    test('multi-character syllables map and complete', () {
      // "pré" = consonant pr (DF) + vowel é (FR); exercises multi-char parsing.
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, 'pré', AlgType.Edge);
      expect(exp, isNotNull);
      expect(CubieCube().fromFacelet(exp!), isTrue);
      expect(
          ThreeStyleGeometry.isPairComplete(exp, solved, 'pré', AlgType.Edge),
          isTrue);
    });

    test('matchingPair detects the wrong case', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, 'be', AlgType.Edge)!;
      final match = ThreeStyleGeometry.matchingPair(
          exp, solved, AlgType.Edge, ['ca', 'bi', 'be', 'de']);
      expect(match, 'be');
    });
  }, skip: USE_EDGE_AUDIO_SYLLABLES ? false : 'audio scheme disabled');

  group('detectAlgType (custom-set scheme detection)', () {
    test('empty set → null', () {
      expect(ThreeStyleGeometry.detectAlgType(const []), isNull);
    });

    test('unrecognized pairs → null', () {
      expect(ThreeStyleGeometry.detectAlgType(['YZ', '12']), isNull);
    });

    test('a set that only partly maps → null (one type must map all)', () {
      expect(ThreeStyleGeometry.detectAlgType(['AD', 'YZ']), isNull);
    });

    test('SpeFFz two-letter pairs resolve to corners (tie-break)', () {
      // A two-letter SpeFFz pair maps as both corner and edge; corners win.
      expect(ThreeStyleGeometry.detectAlgType(['AD', 'DA']), AlgType.Corner);
    });

    test('audio-syllable pairs resolve to edges', () {
      expect(ThreeStyleGeometry.detectAlgType(['be', 'pré']), AlgType.Edge);
    }, skip: USE_EDGE_AUDIO_SYLLABLES ? false : 'audio scheme disabled');

    test('alias spellings do not disqualify a custom set', () {
      // The owner writes DB as "sc" as well as "gn"; one unparseable pair
      // would silently turn cube-driving off for the whole set.
      expect(ThreeStyleGeometry.detectAlgType(['sce', 'gne', 'be']),
          AlgType.Edge);
      expect(
          ThreeStyleGeometry.expectedAfterPair(solved, 'sce', AlgType.Edge),
          ThreeStyleGeometry.expectedAfterPair(solved, 'gne', AlgType.Edge));
    }, skip: USE_EDGE_AUDIO_SYLLABLES ? false : 'audio scheme disabled');
  });

  group('2-flips', () {
    const pair = 'UF-DR'; // flip edges UF (piece 1) and DR (piece 4) in place.
    final involved = _edgeFacelets([1, 4]);

    test('expected state is a valid cube', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.TwoFlip)!;
      expect(exp.length, 54);
      expect(CubieCube().fromFacelet(exp), isTrue);
    });

    test('only the two flipped edges change', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.TwoFlip)!;
      for (var i = 0; i < 54; i++) {
        if (!involved.contains(i)) {
          expect(exp[i], solved[i], reason: 'facelet $i outside the flips moved');
        }
      }
    });

    test('a 2-flip is its own inverse (order 2)', () {
      final once = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.TwoFlip)!;
      expect(once == solved, isFalse);
      final twice = ThreeStyleGeometry.expectedAfterPair(once, pair, AlgType.TwoFlip)!;
      expect(twice, solved);
    });

    test('completion detection', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.TwoFlip)!;
      expect(
          ThreeStyleGeometry.isPairComplete(exp, solved, pair, AlgType.TwoFlip),
          isTrue);
      expect(
          ThreeStyleGeometry.isPairComplete(solved, solved, pair, AlgType.TwoFlip),
          isFalse);
    });
  });

  group('2-twists', () {
    const pair = 'E-F'; // twist corners at E (ULB, piece 2) and F (UFL, piece 1).
    final involved = _cornerFacelets([1, 2]);

    test('expected state is a valid cube', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.TwoTwist)!;
      expect(CubieCube().fromFacelet(exp), isTrue);
    });

    test('only the two twisted corners change', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.TwoTwist)!;
      for (var i = 0; i < 54; i++) {
        if (!involved.contains(i)) {
          expect(exp[i], solved[i], reason: 'facelet $i outside the twists moved');
        }
      }
    });

    test('a 2-twist has order 3', () {
      var s = solved;
      for (var i = 0; i < 3; i++) {
        s = ThreeStyleGeometry.expectedAfterPair(s, pair, AlgType.TwoTwist)!;
        if (i < 2) expect(s == solved, isFalse);
      }
      expect(s, solved, reason: 'applying the case three times returns to solved');
    });

    test('completion detection', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.TwoTwist)!;
      expect(
          ThreeStyleGeometry.isPairComplete(exp, solved, pair, AlgType.TwoTwist),
          isTrue);
    });
  });

  group('parity (UFR corner buffer)', () {
    // "A" = target corner ULB (piece 2); swaps buffer URF (0) with it, plus two
    // edges — the expected state uses the buffer's own UF (1) / UR (0).
    const pair = 'A';
    final involved = {..._cornerFacelets([0, 2]), ..._edgeFacelets([1, 0])};

    test('expected state is a valid cube', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Parity)!;
      expect(CubieCube().fromFacelet(exp), isTrue,
          reason: 'a corner + edge double swap must be a legal cube state');
    });

    test('only the two corners and two edges change', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Parity)!;
      for (var i = 0; i < 54; i++) {
        if (!involved.contains(i)) {
          expect(exp[i], solved[i], reason: 'facelet $i outside the parity moved');
        }
      }
    });

    test('parity is its own inverse (order 2)', () {
      final once = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Parity)!;
      expect(once == solved, isFalse);
      final twice = ThreeStyleGeometry.expectedAfterPair(once, pair, AlgType.Parity)!;
      expect(twice, solved);
    });

    test('completion detection', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Parity)!;
      expect(
          ThreeStyleGeometry.isPairComplete(exp, solved, pair, AlgType.Parity),
          isTrue);
    });

    // Solvers pick their own parity edge swap, and it can differ per alg, so
    // the corner swap is what identifies the case.
    test('completes on any rigid edge swap, not just the expected one', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Parity)!;
      for (final edges in [
        [1, 3], // UF/UB
        [0, 2], // UR/UL
        [5, 7], // DF/DB — nowhere near either buffer
        [8, 11], // FR/BR
      ]) {
        // Undo the expected UF/UR swap, then swap the solver's own pair.
        final state =
            _swapEdges(_swapEdges(exp, 1, 0), edges[0], edges[1]);
        expect(
            ThreeStyleGeometry.isPairComplete(
                state, solved, pair, AlgType.Parity),
            isTrue,
            reason: 'edge swap ${edges[0]}/${edges[1]} must complete "A"');
      }
    });

    test('a flipped edge swap does not complete', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Parity)!;
      final state =
          _swapEdges(_swapEdges(exp, 1, 0), 1, 3, flipped: true);
      expect(
          ThreeStyleGeometry.isPairComplete(state, solved, pair, AlgType.Parity),
          isFalse);
    });

    test('the corner swap alone does not complete', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Parity)!;
      expect(
          ThreeStyleGeometry.isPairComplete(
              _swapEdges(exp, 1, 0), solved, pair, AlgType.Parity),
          isFalse,
          reason: 'corners right but no edge swap is a half-executed alg');
    });

    test('more than two edges moved does not complete', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, pair, AlgType.Parity)!;
      final state = _swapEdges(exp, 5, 7); // UF/UR swap plus a second one
      expect(
          ThreeStyleGeometry.isPairComplete(state, solved, pair, AlgType.Parity),
          isFalse,
          reason: 'an unfinished slice tail leaves four edges off home');
    });

    test('the wrong corner swap is reported as another pair', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, 'B', AlgType.Parity)!;
      expect(
          ThreeStyleGeometry.isPairComplete(exp, solved, pair, AlgType.Parity),
          isFalse);
      expect(
          ThreeStyleGeometry.executedOtherPair(
              exp, [solved], AlgType.Parity, ['A', 'B', 'C'],
              shown: pair),
          'B');
    });

    test('a different edge swap still names the executed pair', () {
      final exp = ThreeStyleGeometry.expectedAfterPair(solved, 'B', AlgType.Parity)!;
      final state = _swapEdges(_swapEdges(exp, 1, 0), 5, 7);
      expect(
          ThreeStyleGeometry.executedOtherPair(
              state, [solved], AlgType.Parity, ['A', 'B', 'C'],
              shown: pair),
          'B');
    });
  });

  group('detectAlgType for the new types', () {
    test('dash-separated flip names resolve to 2-flips', () {
      expect(ThreeStyleGeometry.detectAlgType(['UF-DR', 'UL-BR']),
          AlgType.TwoFlip);
    });

    test('dash-separated single-letter pairs resolve to 2-twists', () {
      expect(ThreeStyleGeometry.detectAlgType(['E-F']), AlgType.TwoTwist);
    });

    test('single letters resolve to parity', () {
      expect(ThreeStyleGeometry.detectAlgType(['A', 'B']), AlgType.Parity);
    });
  });
}

// Which facelets belong to the given edge pieces.
Set<int> _edgeFacelets(List<int> pieces) => {
      for (final p in pieces) ...CubieCube.eFacelet[p],
    };

// Swap edge pieces [a] and [b] in [s], optionally landing them flipped.
String _swapEdges(String s, int a, int b, {bool flipped = false}) {
  final out = s.split('');
  final fa = CubieCube.eFacelet[a];
  final fb = CubieCube.eFacelet[b];
  for (var k = 0; k < 2; k++) {
    final t = flipped ? 1 - k : k;
    out[fa[t]] = s[fb[k]];
    out[fb[t]] = s[fa[k]];
  }
  return out.join();
}
