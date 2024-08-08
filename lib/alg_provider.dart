import 'dart:math';

import 'alg_structs.dart';
import 'custom_edges.dart';

abstract class AlgProvider {
  Alg? getNextAlg();

  void reset();

  double getProgression();
}

double _getProgression(int originalLength, int currentLength) {
  return originalLength == 0 ? 1 : 1 - (currentLength + 1) / originalLength;
}

class LetterPairScheme {
  static const Speffz = "ABCDEFGHIJKLMNOPQRSTUVWX";

  static const AudioEdgeConsonants =
      "bcd?fgh?jlmnprstvwxz"; // TODO turn to list
  static const AudioEdgeVowels = "aei?AEI?oOUuèÈéÉ"; // TODO turn to list
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

List<int> _getCollidingIndices(AlgType algType, int index) {
  if (algType == AlgType.Corner) {
    for (List<int> collidingIndices in _cornerCollidingIndices) {
      for (int collidingIndex in collidingIndices) {
        if (collidingIndex == index) {
          return collidingIndices;
        }
      }
    }
  } else {
    // TODO edges
  }

  return [];
}

List<int> _getBufferIndices(AlgType algType, String buffer) {
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
      required String scheme,
      required List<int> setIndices}) {
    for (int setIndex in setIndices) {
      assert(setIndex > 0 && setIndex < scheme.length);
      List<int> collidingIndices = _getCollidingIndices(algType, setIndex);
      List<int> bufferIndices = _getBufferIndices(algType, buffer);
      var l1 = scheme[setIndex];
      for (int l2Index = 0; l2Index < scheme.length; ++l2Index) {
        var l2 = scheme[l2Index];
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
  void reset() {
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
  void reset() {
    letterPairsToExecute = List.from(letterPairs);
  }

  @override
  double getProgression() {
    return _getProgression(letterPairs.length, letterPairsToExecute.length);
  }
}

class CornersAlgProvider extends LetterPairProvider {
  // TODO set and buffer
  CornersAlgProvider()
      : super(
          algType: AlgType.Corner,
          buffer: "UFR",
          scheme: LetterPairScheme.Speffz,
          setIndices: [1],
        );
}

class EdgesAlgProvider extends CustomProvider {
  EdgesAlgProvider() : super.fromFileContent(CustomEdges.TEST);
}
