enum AlgType {
  Corner,
  Edge,
  TwoFlip,
  TwoTwist,
  Custom,
}

class Alg {
  final String name;

  const Alg(this.name);
}

class AlgTime {
  final int index;
  final int timeMs;
  final Alg alg;

  const AlgTime(this.index, this.timeMs, this.alg);
}

// Aggregated times for a single alg, built from the results history.
class AlgStats {
  final String alg;
  final int count;
  final int minMs;
  final int maxMs;
  final double avgMs;

  const AlgStats(this.alg, this.count, this.minMs, this.maxMs, this.avgMs);

  AlgStats.fromMap(Map<String, Object?> map)
      : alg = map["alg"] as String,
        count = (map["count"] as num).toInt(),
        minMs = (map["minMs"] as num).toInt(),
        maxMs = (map["maxMs"] as num).toInt(),
        avgMs = (map["avgMs"] as num).toDouble();
}

// A single recorded attempt (one row of the results history).
class AlgResult {
  final int id;
  final int resultMs;
  final int timestamp;

  const AlgResult(this.id, this.resultMs, this.timestamp);

  AlgResult.fromMap(Map<String, Object?> map)
      : id = (map["id"] as num).toInt(),
        resultMs = (map["resultMs"] as num).toInt(),
        timestamp = (map["timestamp"] as num).toInt();
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
