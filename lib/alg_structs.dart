enum AlgType {
  Corner,
  Edge,
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
