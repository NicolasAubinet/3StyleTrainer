import 'dart:math';

import 'package:three_style_trainer/settings.dart';

import 'alg_structs.dart';

const bool USE_EDGE_AUDIO_SYLLABLES = false;

abstract class AlgProvider {
  Alg? getNextAlg();

  void reset({List<String> skippedAlgs = const []});

  double getProgression();
}

double _getProgression(int originalLength, int currentLength) {
  return originalLength == 0 ? 1 : 1 - (currentLength + 1) / originalLength;
}

List<String> getAlgSets(AlgType algType) {
  if (algType == AlgType.Edge) {
    if (USE_EDGE_AUDIO_SYLLABLES) {
      return LetterPairScheme.AudioEdgeConsonants;
    } else {
      return Settings().getEdgesScheme();
    }
  } else if (algType == AlgType.Corner) {
    return Settings().getCornersScheme();
  } else {
    throw UnimplementedError();
  }
}

class LetterPairScheme {
  static const AudioEdgeConsonants = [
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

  static const AudioEdgeVowels = [
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
    'é',
    'É',
    'AN',
    'IN',
    'ON',
    'OU',
    'an',
    'in',
    'on',
    'ou',
  ];
}

class CollidingIndices {
  // indices to different stickers of same pieces

  static const List<List<int>> cornerSpeffz = [
    [0, 4, 17],
    [1, 13, 16],
    [2, 9, 12],
    [3, 5, 8],
    [20, 6, 11],
    [21, 10, 15],
    [22, 14, 19],
    [23, 7, 18],
  ];

  static const List<List<int>> edgeSpeffz = [
    [0, 16],
    [1, 12],
    [2, 8],
    [3, 4],
    [5, 11],
    [6, 23],
    [7, 17],
    [9, 15],
    [13, 19],
    [10, 20],
    [18, 22],
    [14, 21],
  ];

  // use a different list to allow to control the order in the list
  static const List<List<int>> edgeAudioSyllables = [
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
}

List<int> _getCollidingIndices(AlgType algType, int index) {
  List<List<int>> collidingIndicesList;
  if (algType == AlgType.Corner) {
    collidingIndicesList = CollidingIndices.cornerSpeffz;
  } else {
    if (USE_EDGE_AUDIO_SYLLABLES) {
      collidingIndicesList = CollidingIndices.edgeAudioSyllables;
    } else {
      collidingIndicesList = CollidingIndices.edgeSpeffz;
    }
  }

  for (List<int> collidingIndices in collidingIndicesList) {
    for (int collidingIndex in collidingIndices) {
      if (collidingIndex == index) {
        return collidingIndices;
      }
    }
  }
  return [];
}

List<int> getCornerBufferIndices(CornerBuffer buffer) {
  switch (buffer) {
    case CornerBuffer.UFR:
      return [2, 9, 12];
    case CornerBuffer.UFL:
      return [3, 5, 8];
    case CornerBuffer.UBR:
      return [1, 13, 16];
    case CornerBuffer.UBL:
      return [0, 4, 17];
    case CornerBuffer.DFR:
      return [10, 15, 21];
    case CornerBuffer.DFL:
      return [6, 11, 20];
  }
}

List<int> getEdgeBufferIndices(EdgeBuffer buffer) {
  if (USE_EDGE_AUDIO_SYLLABLES) {
    return [3, 7];
  }

  switch (buffer) {
    case EdgeBuffer.UF:
      return [2, 8];
    case EdgeBuffer.UB:
      return [0, 16];
    case EdgeBuffer.UR:
      return [1, 12];
    case EdgeBuffer.UL:
      return [3, 4];
    case EdgeBuffer.FR:
      return [9, 15];
    case EdgeBuffer.FL:
      return [11, 5];
    case EdgeBuffer.DF:
      return [20, 10];
    case EdgeBuffer.DB:
      return [22, 18];
    case EdgeBuffer.DR:
      return [21, 14];
    case EdgeBuffer.DL:
      return [23, 6];
  }
}

List<int> getBufferIndices(AlgType algType) {
  List<int> bufferIndices = [];
  if (algType == AlgType.Corner) {
    bufferIndices = getCornerBufferIndices(Settings().getCornerBuffer());
  } else if (algType == AlgType.Edge) {
    bufferIndices = getEdgeBufferIndices(Settings().getEdgeBuffer());
  }
  return bufferIndices;
}

class LetterPairProvider implements AlgProvider {
  var originalLetterPairs = <Alg>[];
  var letterPairsToExecute = <Alg>[];
  int originalPairsToExecute = 0;

  LetterPairProvider({
    required AlgType algType,
    required List<int> setIndices,
    bool invertedAlgs = false,
    List<String> skippedAlgs = const [],
  }) {
    List<String> scheme = getAlgSets(algType);
    List<String>?
        secondLetterScheme; // for custom schemes where the second letter is from a different set than the first
    if (algType == AlgType.Edge && USE_EDGE_AUDIO_SYLLABLES) {
      secondLetterScheme = LetterPairScheme.AudioEdgeVowels;
      assert(scheme.length == secondLetterScheme.length);
    }

    List<int> bufferIndices = getBufferIndices(algType);
    List<int> actualSetIndices = List.from(setIndices);
    if (actualSetIndices.isEmpty) {
      // empty set means all sets
      for (int i = 0; i < scheme.length; ++i) {
        if (!bufferIndices.contains(i)) {
          actualSetIndices.add(i);
        }
      }
    }

    for (int setIndex in actualSetIndices) {
      assert(setIndex >= 0 && setIndex < scheme.length);
      List<int> collidingIndices = _getCollidingIndices(algType, setIndex);
      for (int l2Index = 0; l2Index < scheme.length; ++l2Index) {
        if (!collidingIndices.contains(l2Index) &&
            !bufferIndices.contains(setIndex) &&
            !bufferIndices.contains(l2Index)) {
          addToOriginalLetterPairs(
              setIndex, l2Index, scheme, secondLetterScheme);
          if (invertedAlgs) {
            addToOriginalLetterPairs(
                l2Index, setIndex, scheme, secondLetterScheme);
          }
        }
      }
    }
    reset(skippedAlgs: skippedAlgs);
  }

  void addToOriginalLetterPairs(int l1Index, int l2Index, List<String> scheme,
      List<String>? secondLetterScheme) {
    String l1 = scheme[l1Index];
    String l2 = secondLetterScheme == null
        ? scheme[l2Index]
        : secondLetterScheme[l2Index];
    originalLetterPairs.add(Alg(l1 + l2));
  }

  @override
  Alg? getNextAlg() {
    if (letterPairsToExecute.isEmpty) {
      return null;
    }
    var random = Random();
    var index = random.nextInt(letterPairsToExecute.length);
    return letterPairsToExecute.removeAt(index);
  }

  @override
  void reset({List<String> skippedAlgs = const []}) {
    letterPairsToExecute = List.from(originalLetterPairs);
    letterPairsToExecute.removeWhere((alg) => skippedAlgs.contains(alg.name));
    originalPairsToExecute = letterPairsToExecute.length;
  }

  @override
  double getProgression() {
    return _getProgression(originalPairsToExecute, letterPairsToExecute.length);
  }
}

class CustomProvider implements AlgProvider {
  final List<String> letterPairs;
  List<String> letterPairsToExecute = [];
  int originalPairsToExecute = 0;

  CustomProvider(this.letterPairs) {
    reset();
  }

  CustomProvider.fromFileContent(String multiLineContent)
      : letterPairs = multiLineContent.split('\n') {
    letterPairs.removeWhere((e) {
      return e.trim().isEmpty;
    });
    reset();
  }

  @override
  Alg? getNextAlg() {
    if (letterPairsToExecute.isEmpty) {
      return null;
    }
    var random = Random();
    var index = random.nextInt(letterPairsToExecute.length);
    return Alg(letterPairsToExecute.removeAt(index));
  }

  @override
  void reset({List<String> skippedAlgs = const []}) {
    letterPairsToExecute = List.from(letterPairs);
    letterPairsToExecute.removeWhere((alg) => skippedAlgs.contains(alg));
    originalPairsToExecute = letterPairsToExecute.length;
  }

  @override
  double getProgression() {
    return _getProgression(originalPairsToExecute, letterPairsToExecute.length);
  }
}

class CornersAlgProvider extends LetterPairProvider {
  CornersAlgProvider(
      {super.setIndices = const [],
      super.skippedAlgs = const [],
      super.invertedAlgs = false})
      : super(
          algType: AlgType.Corner,
        );
}

class EdgesAlgProvider extends LetterPairProvider {
  EdgesAlgProvider(
      {super.setIndices = const [],
      super.skippedAlgs = const [],
      super.invertedAlgs = false})
      : super(
          algType: AlgType.Edge,
        );
}

// class EdgesAlgProvider extends CustomProvider {
//   EdgesAlgProvider() : super.fromFileContent(CustomEdges.TEST);
// }
