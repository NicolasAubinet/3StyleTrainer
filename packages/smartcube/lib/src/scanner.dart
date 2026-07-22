import 'driver.dart';
import 'model/connection.dart';
import 'smart_cube.dart';

/// Scans for smart cubes and connects to one, auto-detecting the brand from the
/// advertised name / service UUID. The single entry point for consumers.
abstract class CubeScanner {
  /// Emits cubes as they are discovered. Re-emits with updated fields (e.g. once
  /// a MAC is resolved). Stops when the returned subscription is cancelled.
  Stream<DiscoveredCube> scan();

  /// Every advertisement [scan] sees, including devices no driver claimed.
  /// Triage aid for a model whose advertised name/service isn't known yet.
  Stream<CubeAdvertisement> get advertisements;

  /// Connect to a discovered cube. [macAddress] is required only when
  /// [DiscoveredCube.needsMac] is true (colon-separated, e.g. `CF:30:16:00:AB:CD`).
  Future<SmartCube> connect(DiscoveredCube cube, {String? macAddress});

  Future<void> stopScan();
}
