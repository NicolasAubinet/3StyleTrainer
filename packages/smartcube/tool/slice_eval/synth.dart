/// Notation parsing + the forward synthesizer: solver-frame alg -> the
/// quarter-turn stream a smart cube would report, with timestamps.

import 'dart:math';
import 'algebra.dart';

List<Move> parseAlg(String s) {
  final out = <Move>[];
  for (final tok in s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
    out.add(parseMove(tok));
  }
  return out;
}

Move parseMove(String tok) {
  var t = tok;
  var amount = 1;
  if (t.endsWith("'")) {
    amount = 3;
    t = t.substring(0, t.length - 1);
  } else if (t.endsWith('2')) {
    amount = 2;
    t = t.substring(0, t.length - 1);
  }
  if (t.length == 2 && t[1] == 'w') {
    return Move(MoveKind.wide, faceNames.indexOf(t[0]), amount);
  }
  if (t.length == 1 && t.toLowerCase() == t && 'xyz'.contains(t)) {
    return Move(MoveKind.rotation, 'xyz'.indexOf(t), amount);
  }
  if (t.length == 1 && 'MES'.contains(t)) {
    return Move(MoveKind.slice, 'MES'.indexOf(t), amount);
  }
  if (t.length == 1 && 'rludfb'.contains(t)) {
    // lowercase = wide, classic notation
    return Move(MoveKind.wide, faceNames.indexOf(t.toUpperCase()), amount);
  }
  final f = faceNames.indexOf(t);
  if (f < 0) throw FormatException('bad move token: $tok');
  return Move(MoveKind.outer, f, amount);
}

String algToString(List<Move> alg) => alg.map((m) => m.notation).join(' ');

// ---------------------------------------------------------------------------
// Reported stream
// ---------------------------------------------------------------------------

/// A single reported quarter turn, in the CUBE frame.
class Reported {
  final int face;

  /// true = counter-clockwise (prime)
  final bool prime;
  final int tMs;
  const Reported(this.face, this.prime, this.tMs);

  String get notation => '${faceNames[face]}${prime ? "'" : ""}';
  @override
  String toString() => '$notation@$tMs';
}

class SynthResult {
  final List<Reported> stream;
  final List<int> finalDrift;
  const SynthResult(this.stream, this.finalDrift);
}

/// A group of quarter turns that belong to one physical motion.
class _Group {
  final List<List<int>> quarters; // [face, dirAmount(1|3)]
  final int spreadMs;
  final bool isOuterSingleFace;
  final int? faceIfOuter;
  _Group(this.quarters, this.spreadMs, this.isOuterSingleFace, this.faceIfOuter);
}

class SynthConfig {
  /// Probability an adjacent opposite-face outer pair is executed as one
  /// two-handed simultaneous motion (the adversarial confound).
  final double pSimultaneousOuterPair;
  final int gapMinMs;
  final int gapMaxMs;
  final int halfTurnSpreadMs;
  final int sliceSpreadMs;
  final int simulPairSpreadMs;

  /// Timestamp granularity. Models a cube with no usable per-move clock, where
  /// every move in one BLE notification shares a stamp (GoCube, §30). 0 = exact.
  final int quantizeMs;

  /// Extra uniform noise added to every timestamp, in ms.
  final int jitterMs;

  const SynthConfig({
    this.pSimultaneousOuterPair = 0.6,
    this.gapMinMs = 95,
    this.gapMaxMs = 190,
    this.halfTurnSpreadMs = 38,
    this.sliceSpreadMs = 14,
    this.simulPairSpreadMs = 22,
    this.quantizeMs = 0,
    this.jitterMs = 0,
  });
}

/// A half turn is two quarters in whichever direction the hand actually went,
/// so the pair may be CW or CCW. Emitting only CW meant no corpus stream ever
/// contained a counter-clockwise double — which is how a parser bug that read
/// any 2+2 face split as a half slice survived the whole evaluation.
List<List<int>> _quarters(int face, int amount, Random rng) {
  if (amount == 2) {
    final dir = rng.nextBool() ? 1 : 3;
    return [
      [face, dir],
      [face, dir],
    ];
  }
  return [
    [face, amount],
  ];
}

SynthResult synthesize(List<Move> alg, Random rng, [SynthConfig cfg = const SynthConfig()]) {
  var rho = identity; // reported -> solver
  final groups = <_Group>[];

  for (final m in alg) {
    final dec = decompose(m);
    final rhoInv = invert(rho);
    final quarters = <List<int>>[];
    for (final st in dec.sensed) {
      quarters.addAll(_quarters(rhoInv[st.face], st.amount, rng));
    }
    if (quarters.isNotEmpty) {
      final isOuter = m.kind == MoveKind.outer;
      final spread = m.kind == MoveKind.slice
          ? cfg.sliceSpreadMs
          : (quarters.length > 1 ? cfg.halfTurnSpreadMs : 0);
      groups.add(_Group(
        quarters,
        spread,
        isOuter,
        isOuter ? rhoInv[m.id] : null,
      ));
    }
    rho = compose(dec.drift, rho);
  }

  // Merge adjacent single-quarter outer moves on opposite faces into one
  // simultaneous two-handed motion, some of the time.
  final merged = <_Group>[];
  var i = 0;
  while (i < groups.length) {
    final g = groups[i];
    if (i + 1 < groups.length &&
        g.isOuterSingleFace &&
        groups[i + 1].isOuterSingleFace &&
        g.quarters.length == 1 &&
        groups[i + 1].quarters.length == 1 &&
        oppositeFace[g.faceIfOuter!] == groups[i + 1].faceIfOuter &&
        rng.nextDouble() < cfg.pSimultaneousOuterPair) {
      merged.add(_Group(
        [...g.quarters, ...groups[i + 1].quarters],
        cfg.simulPairSpreadMs,
        false,
        null,
      ));
      i += 2;
      continue;
    }
    merged.add(g);
    i++;
  }

  final stream = <Reported>[];
  var t = 0;
  for (final g in merged) {
    t += cfg.gapMinMs + rng.nextInt(cfg.gapMaxMs - cfg.gapMinMs);
    final qs = List<List<int>>.from(g.quarters);
    qs.shuffle(rng);
    for (var k = 0; k < qs.length; k++) {
      final offset = g.spreadMs == 0
          ? 0
          : (qs.length == 1 ? 0 : (g.spreadMs * k) ~/ (qs.length - 1)) +
              rng.nextInt(5);
      stream.add(Reported(qs[k][0], qs[k][1] == 3, t + offset));
    }
    t += g.spreadMs;
  }
  var out = stream;
  if (cfg.jitterMs > 0 || cfg.quantizeMs > 0) {
    out = [
      for (final r in stream)
        Reported(
          r.face,
          r.prime,
          () {
            var t = r.tMs;
            if (cfg.jitterMs > 0) {
              t += rng.nextInt(2 * cfg.jitterMs + 1) - cfg.jitterMs;
            }
            if (cfg.quantizeMs > 0) t = (t ~/ cfg.quantizeMs) * cfg.quantizeMs;
            return t;
          }(),
        )
    ];
  }
  out.sort((a, b) => a.tMs.compareTo(b.tMs));
  return SynthResult(out, rho);
}
