/// A single quarter-turn reported by the cube.
///
/// Smart cubes report quarter turns only; a double turn arrives as two moves.
/// Whole-cube rotations are not moves — the driver filters/derives those from
/// the gyro stream instead.
enum Face { U, D, L, R, F, B }

class CubeMove {
  final Face face;

  /// `true` for a counter-clockwise (prime) turn, `false` for clockwise.
  final bool prime;

  /// The move's timestamp on the *cube's* clock, reconstructed and fitted to
  /// host time (see the clock-sync fit). Monotonic within a connection.
  final Duration cubeTimestamp;

  /// Host-side wall-clock time the move was processed. Present only on the most
  /// recent move of a packet (older moves in the same packet carry `null`).
  final DateTime? hostTimestamp;

  const CubeMove({
    required this.face,
    required this.prime,
    required this.cubeTimestamp,
    this.hostTimestamp,
  });

  String get notation => '${face.name}${prime ? "'" : ""}';

  @override
  String toString() => 'CubeMove($notation @ ${cubeTimestamp.inMilliseconds}ms)';
}
