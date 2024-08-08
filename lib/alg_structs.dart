enum AlgType {
  Corner,
  Edge,
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
