import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/settings.dart';

// Verifies that the generated 2-twist cases are all physically legit: two
// different non-buffer corners twisted in opposite directions.
void main() {
  test('generated 2-twists are all legit', () {
    final scheme = Settings().getCornersScheme(); // SPEFFZ by default
    final letterToIndex = {
      for (int i = 0; i < scheme.length; i++) scheme[i]: i
    };
    final bufferIndices =
        getCornerBufferIndices(Settings().getCornerBuffer()).toSet();

    int cornerOf(int index) =>
        CollidingIndices.cornerSpeffz.indexWhere((g) => g.contains(index));

    final provider = TwoTwistsAlgProvider();
    final seen = <String>{};
    Alg? alg;
    while ((alg = provider.getNextAlg()) != null) {
      final name = alg!.name;
      final parts = name.split('-');
      expect(parts.length, 2, reason: '$name should be two letters');

      final i = letterToIndex[parts[0]]!;
      final j = letterToIndex[parts[1]]!;
      final oi = cornerTwistOrientation(i);
      final oj = cornerTwistOrientation(j);

      expect(oi, isNotNull, reason: '$name: ${parts[0]} is not a twist target');
      expect(oj, isNotNull, reason: '$name: ${parts[1]} is not a twist target');
      expect((oi! + oj!) % 3, 0, reason: '$name: twists are not opposite');
      expect(cornerOf(i), isNot(cornerOf(j)), reason: '$name: same corner');
      expect(bufferIndices.contains(i), isFalse, reason: '$name: buffer piece');
      expect(bufferIndices.contains(j), isFalse, reason: '$name: buffer piece');

      seen.add(name);
    }

    // 7 non-buffer corners -> C(7,2)=21 pairs x 2 orientations x 2 memo orders.
    expect(seen.length, 84);
  });

  test('every non-buffer corner appears in some 2-twist', () {
    final scheme = Settings().getCornersScheme();
    final letterToIndex = {
      for (int i = 0; i < scheme.length; i++) scheme[i]: i
    };
    int cornerOf(int index) =>
        CollidingIndices.cornerSpeffz.indexWhere((g) => g.contains(index));

    final provider = TwoTwistsAlgProvider();
    final corners = <int>{};
    Alg? alg;
    while ((alg = provider.getNextAlg()) != null) {
      for (final letter in alg!.name.split('-')) {
        corners.add(cornerOf(letterToIndex[letter]!));
      }
    }
    expect(corners.length, 7); // all corners except the buffer
  });
}
