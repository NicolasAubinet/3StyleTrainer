import 'package:flutter/widgets.dart';

import 'l10n/app_localizations.dart';

enum AlgType {
  Corner,
  Edge,
  TwoFlip,
  TwoTwist,
  Parity,
  Custom;

  String getLocalizedName(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (this) {
      case AlgType.Corner:
        return l10n.corners;
      case AlgType.Edge:
        return l10n.edges;
      case AlgType.TwoFlip:
        return l10n.flips;
      case AlgType.TwoTwist:
        return l10n.twists;
      case AlgType.Parity:
        return l10n.parity;
      case AlgType.Custom:
        return l10n.custom;
    }
  }
}

class Alg {
  final String name;

  const Alg(this.name);
}

class AlgTime {
  final int index;
  final int timeMs;
  final Alg alg;
  final int timestamp;
  // Recognition part of a smart-cube split; null for press-timed solves.
  final int? recognitionMs;

  const AlgTime(this.index, this.timeMs, this.alg,
      {required this.timestamp, this.recognitionMs});

  // Execution part of the split (total − recognition); null when unsplit.
  int? get executionMs =>
      recognitionMs == null ? null : timeMs - recognitionMs!;
}

// Aggregated times for a single alg, built from the results history. The split
// averages (recognition/execution) cover only smart-cube rows and are null when
// no such row exists; splitCount is how many rows carry a split.
class AlgStats {
  final String alg;
  final int count;
  final int minMs;
  final int maxMs;
  final double avgMs;
  final double? avgRecognitionMs;
  final double? avgExecutionMs;
  final int splitCount;

  const AlgStats(this.alg, this.count, this.minMs, this.maxMs, this.avgMs,
      {this.avgRecognitionMs, this.avgExecutionMs, this.splitCount = 0});

  AlgStats.fromMap(Map<String, Object?> map)
      : alg = map["alg"] as String,
        count = (map["count"] as num).toInt(),
        minMs = (map["minMs"] as num).toInt(),
        maxMs = (map["maxMs"] as num).toInt(),
        avgMs = (map["avgMs"] as num).toDouble(),
        avgRecognitionMs = (map["avgRecognitionMs"] as num?)?.toDouble(),
        avgExecutionMs = (map["avgExecutionMs"] as num?)?.toDouble(),
        splitCount = (map["splitCount"] as num?)?.toInt() ?? 0;
}

// A single recorded attempt (one row of the results history). recognitionMs is
// the smart-cube recognition split; null for press-timed solves.
class AlgResult {
  final int id;
  final int resultMs;
  final int timestamp;
  final int? recognitionMs;

  const AlgResult(this.id, this.resultMs, this.timestamp, {this.recognitionMs});

  AlgResult.fromMap(Map<String, Object?> map)
      : id = (map["id"] as num).toInt(),
        resultMs = (map["resultMs"] as num).toInt(),
        timestamp = (map["timestamp"] as num).toInt(),
        recognitionMs = (map["recognitionMs"] as num?)?.toInt();

  // Execution part of the split (total − recognition); null when unsplit.
  int? get executionMs =>
      recognitionMs == null ? null : resultMs - recognitionMs!;
}

enum CornerBuffer {
  UFR,
  UFL,
  UBR,
  UBL,
  DFR,
  DFL,
}

enum EdgeBuffer {
  UF,
  UB,
  UR,
  UL,
  FR,
  FL,
  DF,
  DB,
  DR,
  DL,
}

class CustomSet {
  String name;
  List<String> algs;

  CustomSet(this.name, this.algs);

  Map<String, Object?> toMap() {
    var map = <String, Object?>{"name": name, "algs": algsToString()};
    return map;
  }

  CustomSet.fromMap(Map<String, Object?> map)
      : name = map["name"] as String,
        algs = (map["algs"] as String).split(",");

  String algsToString() {
    return algs.join(",");
  }
}
