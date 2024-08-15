import 'dart:math';

import 'alg_structs.dart';

abstract class AlgProvider {
  Alg? getNextAlg();

  void reset({List<String> skippedAlgs = const []});

  double getProgression();
}

double _getProgression(int originalLength, int currentLength) {
  return originalLength == 0 ? 1 : 1 - (currentLength + 1) / originalLength;
}

List<String> getAlgSets(AlgType algType) {
  return algType == AlgType.Corner
      ? LetterPairScheme.Speffz
      : LetterPairScheme.AudioEdgeConsonants;
}

class LetterPairScheme {
  static const Speffz = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
  ];

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

List<List<int>> _cornerCollidingIndices = [
  // indices to different stickers of same corner pieces
  [0, 4, 17],
  [1, 13, 16],
  [2, 9, 12],
  [3, 5, 8],
  [20, 6, 11],
  [21, 10, 15],
  [22, 14, 19],
  [23, 7, 18],
];

List<List<int>> _edgeCollidingIndices = [
  // indices to different stickers of same edge pieces
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

List<int> _getCollidingIndices(AlgType algType, int index) {
  List<List<int>> collidingIndicesList;
  if (algType == AlgType.Corner) {
    collidingIndicesList = _cornerCollidingIndices;
  } else {
    collidingIndicesList = _edgeCollidingIndices;
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

List<int> getBufferIndices(AlgType algType, String buffer) {
  if (algType == AlgType.Corner) {
    if (buffer == "UFR") {
      return [2, 9, 12];
    }
  } else if (algType == AlgType.Edge) {
    if (buffer == "UF") {
      return [3, 7];
    }
  }

  throw UnimplementedError();
}

class LetterPairProvider implements AlgProvider {
  var originalLetterPairs = <Alg>[];
  var letterPairsToExecute = <Alg>[];

  LetterPairProvider(
      {required AlgType algType,
      required String buffer,
      required List<String> scheme,
      List<String>?
          secondLetterScheme, // for custom schemes where the second letter is from a different set than the first
      required List<int> setIndices}) {
    if (secondLetterScheme != null) {
      assert(scheme.length == secondLetterScheme.length);
    }

    List<int> bufferIndices = getBufferIndices(algType, buffer);
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
      var l1 = scheme[setIndex];
      for (int l2Index = 0; l2Index < scheme.length; ++l2Index) {
        var l2 = secondLetterScheme == null
            ? scheme[l2Index]
            : secondLetterScheme[l2Index];
        if (!collidingIndices.contains(l2Index) &&
            !bufferIndices.contains(l2Index)) {
          originalLetterPairs.add(Alg(l1 + l2));
        }
      }
    }
    reset();
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
    originalLetterPairs.removeWhere((alg) => skippedAlgs.contains(alg.name));
    letterPairsToExecute = List.from(originalLetterPairs);
  }

  @override
  double getProgression() {
    return _getProgression(
        originalLetterPairs.length, letterPairsToExecute.length);
  }
}

class CustomProvider implements AlgProvider {
  final List<String> letterPairs;
  List<String> letterPairsToExecute = [];

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
    letterPairs.removeWhere((alg) => skippedAlgs.contains(alg));
    letterPairsToExecute = List.from(letterPairs);
  }

  @override
  double getProgression() {
    return _getProgression(letterPairs.length, letterPairsToExecute.length);
  }
}

class CornersAlgProvider extends LetterPairProvider {
  CornersAlgProvider({super.setIndices = const []})
      : super(
          algType: AlgType.Corner,
          buffer: "UFR",
          scheme: LetterPairScheme.Speffz,
        );
}

class EdgesAlgProvider extends LetterPairProvider {
  EdgesAlgProvider({super.setIndices = const []})
      : super(
          algType: AlgType.Edge,
          buffer: "UF",
          scheme: LetterPairScheme.AudioEdgeConsonants,
          secondLetterScheme: LetterPairScheme.AudioEdgeVowels,
        );
}

// class EdgesAlgProvider extends CustomProvider {
//   EdgesAlgProvider() : super.fromFileContent(CustomEdges.TEST);
// }
