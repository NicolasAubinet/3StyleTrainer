/// Bluetooth smart-cube connectivity — brand-agnostic move & state streams.
///
/// GPL-3.0. Portions ported to Dart from csTimer (cs0x7f/cstimer, GPL-3.0).
library;

export 'src/model/connection.dart';
export 'src/model/cube_move.dart';
export 'src/model/cube_state.dart';
export 'src/smart_cube.dart';
export 'src/scanner.dart';
export 'src/driver.dart';
export 'src/scanner_impl.dart' show createCubeScanner, DefaultCubeScanner;
export 'src/transport/ble_transport.dart';
export 'src/cube/cubie_cube.dart' show CubieCube;
export 'src/reconstruct/frame_algebra.dart';
export 'src/reconstruct/move_prior.dart';
export 'src/reconstruct/timing_quality.dart';
export 'src/reconstruct/reconstruction.dart';
export 'src/reconstruct/solver_move.dart';
