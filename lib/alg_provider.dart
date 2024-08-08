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
  final Speffz = "ABCDEFGHIJMLNOPQRSTUVWX";
}

class LetterPairProvider implements AlgProvider {
  final originalLetterPairs = [
    Alg('AB'),
    Alg('AD'),
    Alg('AE'),
  ];
  var letterPairsToExecute = <Alg>[];

  LetterPairProvider() {
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

class CornersAlgProvider extends LetterPairProvider {}

class EdgesAlgProvider extends CustomProvider {
  EdgesAlgProvider() : super.fromFileContent(CustomEdges.TEST);
}
