import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/audio_edge_scheme.dart';

// Validates the audio edge scheme in isolation — independent of the
// USE_EDGE_AUDIO_SYLLABLES build flag, so it always runs.
void main() {
  group('toSpeffz physical mapping', () {
    test('is a bijection over the 24 sticker positions', () {
      expect(AudioEdgeScheme.toSpeffz.length, 24);
      expect(AudioEdgeScheme.toSpeffz.toSet(), {for (var i = 0; i < 24; i++) i});
    });

    test('each audio edge group maps onto one physical SpeFFz edge', () {
      // The strongest correctness check: the audio scheme groups its stickers
      // into edges differently from SpeFFz, but each group must still land on a
      // single real edge once translated into SpeFFz positions.
      final speffzEdges =
          CollidingIndices.edgeSpeffz.map((g) => (List.of(g)..sort())).toList();
      for (final group in AudioEdgeScheme.collisionGroups) {
        final mapped = [
          AudioEdgeScheme.toSpeffz[group[0]],
          AudioEdgeScheme.toSpeffz[group[1]],
        ]..sort();
        expect(speffzEdges.any((e) => e[0] == mapped[0] && e[1] == mapped[1]),
            isTrue,
            reason: 'audio group $group -> $mapped is not a SpeFFz edge');
      }
    });

    test('buffer maps to the SpeFFz UF edge, U-face primary', () {
      expect(AudioEdgeScheme.bufferSpeffz, 2); // SpeFFz UF (U-face) sticker
      final buffer = {
        AudioEdgeScheme.toSpeffz[AudioEdgeScheme.bufferIndices[0]],
        AudioEdgeScheme.toSpeffz[AudioEdgeScheme.bufferIndices[1]],
      };
      expect(buffer, {2, 8}); // SpeFFz UF edge
    });
  });

  group('syllable parsing', () {
    test('format then parse round-trips every lettered sticker pair', () {
      for (var c = 0; c < AudioEdgeScheme.consonants.length; c++) {
        if (AudioEdgeScheme.consonants[c] == '?') continue;
        for (var v = 0; v < AudioEdgeScheme.vowels.length; v++) {
          if (AudioEdgeScheme.vowels[v] == '?') continue;
          final name = AudioEdgeScheme.format(c, v);
          expect(AudioEdgeScheme.parse(name), (c, v),
              reason: 'parse("$name") should be ($c, $v)');
        }
      }
    });

    test('tokenises multi-character consonants and vowels', () {
      expect(AudioEdgeScheme.parse('pré'), (20, 15)); // pr + é (FR)
      expect(AudioEdgeScheme.parse('gna'), (22, 0)); // gn + a
      expect(AudioEdgeScheme.parse('cha'), (23, 0)); // ch + a
      expect(AudioEdgeScheme.parse('bAN'), (0, 16)); // b + AN
      expect(AudioEdgeScheme.parse('bou'), (0, 23)); // b + ou
    });

    test('a short consonant never preempts a longer valid one', () {
      // "pr…" must not parse as p + (r…): no vowel starts with r/n/h.
      expect(AudioEdgeScheme.parse('pran'), (20, 20)); // pr + an, not p + ran
      expect(AudioEdgeScheme.parse('gnon'), (22, 22)); // gn + on, not g + non
    });

    test('rejects names that are not audio pairs', () {
      expect(AudioEdgeScheme.parse('AB'), isNull); // SpeFFz letters
      expect(AudioEdgeScheme.parse(''), isNull);
      expect(AudioEdgeScheme.parse('b'), isNull); // consonant only
    });

    test('alias spellings parse to the same sticker as the canonical one', () {
      // The owner writes DB as both "gn" and "sc"; custom sets may use either.
      expect(AudioEdgeScheme.parse('sce'), AudioEdgeScheme.parse('gne'));
      expect(AudioEdgeScheme.parse('sce'), (22, 1)); // gn/sc + e = UF-DB-UB
      expect(AudioEdgeScheme.parse('scou'), AudioEdgeScheme.parse('gnou'));
      // The alias must not shadow the real "s" consonant (the RF sticker).
      expect(AudioEdgeScheme.parse('se'), (14, 1));
    });
  });
}
