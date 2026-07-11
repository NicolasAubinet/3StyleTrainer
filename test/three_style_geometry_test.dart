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
  });

  test('unsupported alg types return null (for now)', () {
    expect(
        ThreeStyleGeometry.expectedAfterPair(solved, 'UF-DR', AlgType.TwoFlip),
        isNull);
  });
}
