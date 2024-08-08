import 'dart:math';

import 'alg_structs.dart';

abstract class AlgProvider {
  Alg? getNextAlg();
}

class LetterPairScheme {
  final Speffz = "ABCDEFGHIJMLNOPQRSTUVWX";
}

class LetterPairProvider implements AlgProvider {
  final letterPairs = [
    Alg('AB'),
    Alg('AD'),
    Alg('AE'),
  ];

  @override
  Alg? getNextAlg() {
    if (letterPairs.isEmpty) {
      return null;
    }
    var random = Random();
    var index = random.nextInt(letterPairs.length);
    return letterPairs.removeAt(index);
  }
}

class CustomProvider implements AlgProvider {
  final List<String> letterPairs;

  const CustomProvider(this.letterPairs);

  CustomProvider.fromFileContent(String multiLineContent)
      : letterPairs = multiLineContent.split('\n') {
    letterPairs.removeWhere((e) {
      return e.trim().isEmpty;
    });
  }

  @override
  Alg? getNextAlg() {
    if (letterPairs.isEmpty) {
      return null;
    }
    var random = Random();
    var index = random.nextInt(letterPairs.length);
    return Alg(letterPairs.removeAt(index));
  }
}
