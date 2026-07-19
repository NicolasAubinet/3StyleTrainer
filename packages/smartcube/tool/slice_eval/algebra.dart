/// Cube frame algebra for slice/wide reconstruction (plan §31a).
///
/// Faces are indexed U=0 D=1 L=2 R=3 F=4 B=5.
/// A rotation is a permutation `p` where `p[f]` = the position face `f` moves to.

const int U = 0, D = 1, L = 2, R = 3, F = 4, B = 5;
const List<String> faceNames = ['U', 'D', 'L', 'R', 'F', 'B'];

/// x follows R: F->U, U->B, B->D, D->F; R,L fixed.
const List<int> rotX = [B, F, L, R, U, D];

/// y follows U: F->L, L->B, B->R, R->F; U,D fixed.
const List<int> rotY = [U, D, B, F, L, R];

/// z follows F: U->R, R->D, D->L, L->U; F,B fixed.
const List<int> rotZ = [R, L, U, D, F, B];

const List<int> identity = [U, D, L, R, F, B];

/// (a . b)[f] = a[b[f]]
List<int> compose(List<int> a, List<int> b) =>
    List<int>.generate(6, (f) => a[b[f]]);

List<int> invert(List<int> p) {
  final inv = List<int>.filled(6, 0);
  for (var f = 0; f < 6; f++) {
    inv[p[f]] = f;
  }
  return inv;
}

List<int> power(List<int> p, int n) {
  var acc = identity;
  for (var i = 0; i < n; i++) {
    acc = compose(p, acc);
  }
  return acc;
}

String rotKey(List<int> p) => p.join(',');

/// The 24 orientations, generated from x and y.
List<List<int>> buildRotationGroup() {
  final seen = <String, List<int>>{};
  final queue = <List<int>>[identity];
  seen[rotKey(identity)] = identity;
  while (queue.isNotEmpty) {
    final cur = queue.removeLast();
    for (final g in [rotX, rotY, rotZ]) {
      final next = compose(g, cur);
      if (!seen.containsKey(rotKey(next))) {
        seen[rotKey(next)] = next;
        queue.add(next);
      }
    }
  }
  return seen.values.toList();
}

// ---------------------------------------------------------------------------
// Moves
// ---------------------------------------------------------------------------

enum MoveKind { outer, slice, wide, rotation }

/// amount: 1 = CW, 2 = 180, 3 = CCW.
class Move {
  final MoveKind kind;

  /// outer/wide -> face index. slice -> 0=M 1=E 2=S. rotation -> 0=x 1=y 2=z.
  final int id;
  final int amount;

  const Move(this.kind, this.id, this.amount);

  String get notation {
    final suffix = amount == 1 ? '' : (amount == 2 ? '2' : "'");
    switch (kind) {
      case MoveKind.outer:
        return '${faceNames[id]}$suffix';
      case MoveKind.wide:
        return '${faceNames[id]}w$suffix';
      case MoveKind.slice:
        return '${['M', 'E', 'S'][id]}$suffix';
      case MoveKind.rotation:
        return '${['x', 'y', 'z'][id]}$suffix';
    }
  }

  @override
  String toString() => notation;

  @override
  bool operator ==(Object other) =>
      other is Move && other.kind == kind && other.id == id && other.amount == amount;

  @override
  int get hashCode => Object.hash(kind, id, amount);
}

int inverseAmount(int a) => a == 2 ? 2 : (a == 1 ? 3 : 1);

/// One sensed quarter/half turn on a face, in whatever frame the caller is using.
class SensedTurn {
  final int face;
  final int amount;
  const SensedTurn(this.face, this.amount);
}

/// What the cube senses for a move, expressed in the SOLVER frame, plus the
/// room-frame core rotation the move imparts.
class Decomposition {
  final List<SensedTurn> sensed;
  final List<int> drift;
  const Decomposition(this.sensed, this.drift);
}

/// Slice sensed pairs and core rotations (plan §31a).
///   M  = R + L'  , rho = x'      E  = U + D'  , rho = y'
///   S  = F' + B  , rho = z
Decomposition decomposeSlice(int sliceId, int amount) {
  late int faceA, faceB;
  late int dirA, dirB;
  late List<int> axis;
  switch (sliceId) {
    case 0: // M: R + L', follows L -> x'
      faceA = R;
      faceB = L;
      dirA = 1;
      dirB = 3;
      axis = invert(rotX);
      break;
    case 1: // E: U + D', follows D -> y'
      faceA = U;
      faceB = D;
      dirA = 1;
      dirB = 3;
      axis = invert(rotY);
      break;
    default: // S: F' + B, follows F -> z
      faceA = F;
      faceB = B;
      dirA = 3;
      dirB = 1;
      axis = rotZ;
      break;
  }
  if (amount == 2) {
    return Decomposition(
      [SensedTurn(faceA, 2), SensedTurn(faceB, 2)],
      power(axis, 2),
    );
  }
  if (amount == 3) {
    return Decomposition(
      [SensedTurn(faceA, inverseAmount(dirA)), SensedTurn(faceB, inverseAmount(dirB))],
      invert(axis),
    );
  }
  return Decomposition(
    [SensedTurn(faceA, dirA), SensedTurn(faceB, dirB)],
    axis,
  );
}

const Map<int, int> oppositeFace = {U: D, D: U, L: R, R: L, F: B, B: F};

/// Which slice a wide move carries, and hence its drift.
///   Rw = R M' -> sensed L (same amount), rho = x
///   Uw = U E' -> sensed D            , rho = y
///   Fw = F S  -> sensed B            , rho = z
Decomposition decomposeWide(int face, int amount) {
  late List<int> baseAxis;
  late bool inverted;
  switch (face) {
    case R:
      baseAxis = rotX;
      inverted = false;
      break;
    case L:
      baseAxis = invert(rotX);
      inverted = false;
      break;
    case U:
      baseAxis = rotY;
      inverted = false;
      break;
    case D:
      baseAxis = invert(rotY);
      inverted = false;
      break;
    case F:
      baseAxis = rotZ;
      inverted = false;
      break;
    default: // B
      baseAxis = invert(rotZ);
      inverted = false;
      break;
  }
  final drift = amount == 2
      ? power(baseAxis, 2)
      : (amount == 3 ? invert(baseAxis) : baseAxis);
  // Sensed: the opposite face, same amount.
  final sensedAmount = amount;
  return Decomposition(
    [SensedTurn(oppositeFace[face]!, sensedAmount)],
    inverted ? invert(drift) : drift,
  );
}

List<int> rotationDrift(int axisId, int amount) {
  final base = [rotX, rotY, rotZ][axisId];
  if (amount == 2) return power(base, 2);
  if (amount == 3) return invert(base);
  return base;
}

/// Full decomposition of any solver-frame move.
Decomposition decompose(Move m) {
  switch (m.kind) {
    case MoveKind.outer:
      return Decomposition([SensedTurn(m.id, m.amount)], identity);
    case MoveKind.slice:
      return decomposeSlice(m.id, m.amount);
    case MoveKind.wide:
      return decomposeWide(m.id, m.amount);
    case MoveKind.rotation:
      return Decomposition([], rotationDrift(m.id, m.amount));
  }
}

/// Two simultaneous turns on opposite faces reach the cube in an arbitrary
/// order — it cannot know which landed first, so neither can we. Sort adjacent
/// opposite-face outer pairs before comparing, or every one is a false miss.
List<Move> canonical(List<Move> alg) {
  final out = List<Move>.from(alg);
  for (var i = 0; i + 1 < out.length; i++) {
    final a = out[i], b = out[i + 1];
    if (a.kind == MoveKind.outer &&
        b.kind == MoveKind.outer &&
        oppositeFace[a.id] == b.id &&
        a.id > b.id) {
      out[i] = b;
      out[i + 1] = a;
    }
  }
  return out;
}

/// [canonical], plus collapsing a double executed as two quarter turns: the
/// cube cannot tell `M' M'` from `M2` and neither should a comparison.
List<Move> canonicalCollapsed(List<Move> alg) {
  final out = <Move>[];
  for (final m in canonical(alg)) {
    if (out.isNotEmpty) {
      final p = out.last;
      if (p.kind == m.kind &&
          p.id == m.id &&
          p.amount == m.amount &&
          m.amount != 2) {
        out[out.length - 1] = Move(m.kind, m.id, 2);
        continue;
      }
    }
    out.add(m);
  }
  return out;
}
