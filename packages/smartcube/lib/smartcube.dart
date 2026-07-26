/// Bluetooth smart-cube connectivity — brand-agnostic move & state streams.
///
/// GPL-3.0. Portions ported to Dart from csTimer (cs0x7f/cstimer, GPL-3.0).
library;

export 'src/model/connection.dart';
export 'src/model/cube_error.dart';
export 'src/model/cube_move.dart';
export 'src/model/cube_state.dart';
export 'src/smart_cube.dart';
export 'src/scanner.dart';
export 'src/driver.dart';
export 'src/scanner_impl.dart' show createCubeScanner, DefaultCubeScanner;
export 'src/transport/ble_transport.dart';
export 'src/cube/cubie_cube.dart' show CubieCube;
// Slice reconstruction. Only what a caller needs to run it and read the answer
// — the frame algebra underneath (compose, decomposeSlice, toSolverFrame, the
// rotation constants) stays internal on purpose. Its drift conventions are
// pinned to measured hardware, so publishing them would freeze them, and the
// package's own tests and example import src/reconstruct/... directly instead.
export 'src/reconstruct/frame_algebra.dart' show FaceRotation, Slice, kIdentity;
export 'src/reconstruct/move_prior.dart' show ReconstructionWeights;
export 'src/reconstruct/timing_quality.dart' show TimingQuality;
export 'src/reconstruct/reconstruction.dart' show Reconstruction, reconstruct;
export 'src/reconstruct/solver_move.dart'
    show MoveKind, SolverMove, movesToString;
