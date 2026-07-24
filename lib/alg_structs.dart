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
  // The moves of this solve in the user's holding frame; session-only, never
  // persisted. Null for press-timed solves.
  final String? moves;
  // False when [moves] is the raw face-by-face reading rather than a
  // reconstruction — slices were not recovered and none should be inferred.
  final bool movesReconstructed;

  const AlgTime(this.index, this.timeMs, this.alg,
      {required this.timestamp,
      this.recognitionMs,
      this.moves,
      this.movesReconstructed = true});

  // Execution part of the split (total − recognition); null when unsplit.
  int? get executionMs =>
      recognitionMs == null ? null : timeMs - recognitionMs!;
}

enum AlgMistakeKind { wrongCase, requeued, skipped }

// A case that went wrong in a cube-driven run: it was abandoned so it has no
// honest time and never reaches the results history. A requeued case goes back
// in the pool; a skipped one is dropped from the rest of the session.
class AlgMistake {
  final int index;
  final Alg alg;
  final AlgMistakeKind kind;
  // The pair the cube says was actually executed; null when nothing matched and
  // the user requeued the case.
  final String? executed;
  // The moves actually turned on this attempt, in the user's holding frame
  // (e.g. "R U R' U'"). Empty when the cube saw none.
  final String? moves;
  // False when [moves] is a raw reading (no slices recovered); session-only,
  // deliberately not persisted with the moves string.
  final bool movesReconstructed;

  const AlgMistake(this.index, this.alg, this.kind,
      {this.executed, this.moves, this.movesReconstructed = true});
}

// Aggregated mistakes for one alg (built from the mistakes history): how many
// times it went wrong, the breakdown by kind, and when it last happened.
class AlgMistakeStats {
  final String alg;
  final int count;
  final Map<AlgMistakeKind, int> kindCounts;
  final int lastTimestamp;

  const AlgMistakeStats(
      this.alg, this.count, this.kindCounts, this.lastTimestamp);
}

// A single recorded slip, for the per-case error detail list. [kind] is null
// only if an unknown kind name was stored.
class AlgMistakeEntry {
  final AlgMistakeKind? kind;
  final String? executed;
  final String? moves;
  final int timestamp;

  const AlgMistakeEntry(
      {required this.kind, required this.timestamp, this.executed, this.moves});
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
