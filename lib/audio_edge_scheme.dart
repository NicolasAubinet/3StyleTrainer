/// The owner's personal French audio-syllable **edge** lettering — a scheme
/// entirely separate from the standard SpeFFz path, kept isolated here.
///
/// Each edge sticker gets a *consonant* (used when it is the FIRST sticker of a
/// pair) and a *vowel* (used when it is the SECOND). A pair name is
/// `consonant + vowel` with no separator; syllables can be multiple characters
/// (`pr`, `gn`, `ch`, `AN`, …), so parsing splits by the longest valid consonant
/// prefix whose remainder is a valid vowel. `?` entries are the (unlettered)
/// buffer gaps.
///
/// Crucially, this scheme also *reorders physical sticker positions* relative to
/// SpeFFz (its edges group differently — see [collisionGroups]). [toSpeffz] maps
/// each audio sticker index onto the SpeFFz position index of the SAME physical
/// facelet, so completion geometry can run entirely in SpeFFz space (see
/// `ThreeStyleGeometry`) rather than duplicating the facelet model.
class AudioEdgeScheme {
  static const List<String> consonants = [
    'b',
    'c',
    'd',
    '?',
    'f',
    'g',
    'h',
    '?',
    'j',
    'l',
    'm',
    'n',
    'p',
    'r',
    's',
    't',
    'v',
    'w',
    'x',
    'z',
    'pr',
    'y',
    'gn',
    'ch',
  ];

  static const List<String> vowels = [
    'a',
    'e',
    'i',
    '?',
    'A',
    'E',
    'I',
    '?',
    'o',
    'O',
    'U',
    'u',
    'è',
    'È',
    'É',
    'é',
    'AN',
    'IN',
    'ON',
    'OU',
    'an',
    'in',
    'on',
    'ou',
  ];

  // The two sticker indices forming each physical edge (same-edge stickers can't
  // pair). A different ordering from SpeFFz on purpose — it drives enumeration.
  static const List<List<int>> collisionGroups = [
    [0, 4],
    [1, 5],
    [2, 6],
    [3, 7],
    [8, 9],
    [10, 11],
    [12, 13],
    [14, 15],
    [16, 20],
    [17, 21],
    [18, 22],
    [19, 23],
  ];

  // The buffer edge's two sticker indices (physically UF); index 3 is the U-face
  // primary, matching SpeFFz's UF buffer reference.
  static const List<int> bufferIndices = [3, 7];

  // audio sticker index -> SpeFFz position index of the SAME physical facelet.
  // Derived from the owner's physical lettering and validated against
  // [collisionGroups] (every group maps to one SpeFFz edge). See
  // docs/smart-cube-integration-plan.md §15.
  static const List<int> toSpeffz = [
    3, 0, 1, 2, 4, 16, 12, 8, 11, 5, 7, 17, //
    19, 13, 15, 9, 10, 6, 18, 14, 20, 23, 22, 21,
  ];

  /// SpeFFz position index of the buffer's primary (U-face) sticker.
  static int get bufferSpeffz => toSpeffz[bufferIndices.first];

  /// The (consonant, vowel) sticker indices a pair name denotes, or null if the
  /// name isn't a valid audio pair. Splits by longest valid consonant prefix
  /// whose remainder is exactly a vowel — unambiguous because no vowel starts
  /// with a consonant continuation (`r`, `n`, `h`, …).
  static (int, int)? parse(String pair) {
    for (int ci = 0; ci < consonants.length; ci++) {
      final c = consonants[ci];
      if (c == '?' || !pair.startsWith(c)) continue;
      final rest = pair.substring(c.length);
      final vi = vowels.indexOf(rest);
      if (vi >= 0 && vowels[vi] != '?') return (ci, vi);
    }
    return null;
  }

  /// The two SpeFFz position indices of a pair's stickers (for completion
  /// geometry), or null if the name isn't a valid audio pair.
  static (int, int)? parseToSpeffz(String pair) {
    final p = parse(pair);
    if (p == null) return null;
    return (toSpeffz[p.$1], toSpeffz[p.$2]);
  }

  /// Build the pair name from a consonant index and a vowel index.
  static String format(int consonantIndex, int vowelIndex) =>
      consonants[consonantIndex] + vowels[vowelIndex];
}
