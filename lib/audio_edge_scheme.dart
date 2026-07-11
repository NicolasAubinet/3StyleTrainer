/// The owner's personal French audio-syllable edge lettering, kept isolated from
/// the standard SpeFFz path. A pair name is `consonant + vowel` (each possibly
/// multi-character, so parsing uses longest-valid-prefix; `?` = buffer gap). The
/// scheme reorders physical positions vs SpeFFz, so [toSpeffz] maps each audio
/// index onto the SpeFFz position of the same facelet — letting completion
/// geometry run in SpeFFz space instead of duplicating the facelet model.
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

  // The two sticker indices forming each physical edge (same-edge can't pair).
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

  // Buffer edge UF; index 3 is the U-face primary (matches SpeFFz's UF buffer).
  static const List<int> bufferIndices = [3, 7];

  // audio sticker index -> SpeFFz position of the same facelet (validated in
  // tests: every collisionGroup maps to one SpeFFz edge).
  static const List<int> toSpeffz = [
    3, 0, 1, 2, 4, 16, 12, 8, 11, 5, 7, 17, //
    19, 13, 15, 9, 10, 6, 18, 14, 20, 23, 22, 21,
  ];

  /// SpeFFz position index of the buffer's primary (U-face) sticker.
  static int get bufferSpeffz => toSpeffz[bufferIndices.first];

  /// The (consonant, vowel) indices a pair name denotes, or null. Longest-prefix
  /// consonant split; unambiguous since no vowel starts a consonant continuation.
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
