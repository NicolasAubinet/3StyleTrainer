import 'model/connection.dart';
import 'model/cube_move.dart';
import 'model/cube_state.dart';
import 'reconstruct/timing_quality.dart';

/// A connected smart cube. Brand-agnostic: consumers subscribe to [moves] and
/// [states] and never touch BLE or per-brand protocol.
abstract class SmartCube {
  DiscoveredCube get device;

  /// Quarter-turn events, in order, with fitted timestamps.
  Stream<CubeMove> get moves;

  /// How much this cube's per-move timestamps can be trusted.
  ///
  /// Abstract on purpose: a wrong default here yields confident nonsense from
  /// slice reconstruction, and nothing downstream can detect it, so every
  /// driver has to say which it is.
  TimingQuality get timingQuality;

  /// Full-state snapshots — emitted on connect and after every applied move.
  Stream<CubeState> get states;

  /// Emits when tracking was re-anchored on the cube's own state after moves
  /// were lost (a radio drop, or the cube waking from sleep). Anything holding a
  /// baseline taken before this must re-take it: moves happened that the app
  /// never saw.
  Stream<CubeState> get resyncs;

  Stream<CubeConnection> get connectionEvents;
  CubeConnection get connection;

  /// The last known cube state (integrated from the move stream).
  CubeState get currentState;

  /// Pull a fresh full state from the cube to re-anchor after packet loss.
  Future<CubeState> requestState();

  /// Tell the tracker the cube is now in [state] (e.g. the user solved it by
  /// hand). Realigns the model without a physical resync.
  Future<void> syncState(CubeState state);

  /// Re-zero the gyroscope orientation reference (where supported).
  Future<void> resetGyro();

  /// Battery percentage 0–100, or `null` if unavailable.
  Future<int?> batteryLevel();

  Future<void> disconnect();
}
