import '../model/cube_move.dart';
import '../model/cube_state.dart';

/// One decoded event from a GAN cube's notification stream.
sealed class GanEvent {}

/// The cube's own full state, which re-anchors move tracking.
class GanStateEvent extends GanEvent {
  final CubeState state;
  GanStateEvent(this.state);
}

/// A single move plus the resulting full cube state.
class GanMoveEvent extends GanEvent {
  final CubeMove move;
  final CubeState stateAfter;
  GanMoveEvent(this.move, this.stateAfter);
}

/// More moves happened than could be recovered, so the tracked model no longer
/// matches the cube. Moves are ignored until fresh facelets re-anchor it.
class GanDesyncEvent extends GanEvent {
  /// Moves the cube reported that never reached the model.
  final int lostMoves;
  GanDesyncEvent(this.lostMoves);
}

/// The parser needs moves it never saw. The driver answers by writing
/// [GanProtocol.encodeMoveHistory]; the recovered moves arrive as a normal
/// packet. Gen3/Gen4 only — a Gen2 packet already carries its own history.
class GanHistoryRequestEvent extends GanEvent {
  final int serial;
  final int count;
  GanHistoryRequestEvent(this.serial, this.count);
}

class GanBatteryEvent extends GanEvent {
  final int level;
  GanBatteryEvent(this.level);
}

class GanInfoEvent extends GanEvent {
  final String hardwareName;
  final String hardwareVersion;
  final String softwareVersion;
  final bool gyroSupported;
  GanInfoEvent(this.hardwareName, this.hardwareVersion, this.softwareVersion,
      this.gyroSupported);
}

/// The cube asked to end the session (it is powering down).
class GanDisconnectEvent extends GanEvent {}

/// What the driver can ask a cube for.
enum GanRequest {
  facelets,
  hardware,
  battery,

  /// Tell the cube its current position *is* solved.
  reset,
}

/// One GAN protocol generation. Implementations are PURE — bytes in, events out
/// — so they unit-test from fixtures without hardware.
abstract class GanProtocol {
  /// The encrypted packet for [request], or `null` if this generation has no
  /// such command.
  List<int>? encodeRequest(GanRequest request);

  /// The encrypted packet asking for [count] moves ending at [serial], or `null`
  /// on generations that never ask (Gen2).
  List<int>? encodeMoveHistory(int serial, int count) => null;

  List<GanEvent> parse(List<int> raw, int hostTimeMs);

  CubeState get currentState;

  /// `true` while the model is untrusted: moves are dropped until facelets
  /// re-anchor it.
  bool get needsAnchor;

  int? get batteryLevel;

  /// Realign the tracked model without a physical resync.
  void setState(CubeState state);
}

/// A move held in [GanMoveBuffer], before it is known to be in order.
class BufferedMove {
  final int serial;
  final Face face;
  final bool prime;

  /// The cube's own clock, in ms. `null` for a move recovered from history —
  /// the cube does not stamp those.
  final int? cubeTimeMs;

  /// `null` for a recovered move: it was never seen live, so no host time means
  /// anything for it.
  final int? hostTimeMs;

  const BufferedMove({
    required this.serial,
    required this.face,
    required this.prime,
    this.cubeTimeMs,
    this.hostTimeMs,
  });
}

/// What [GanMoveBuffer] concluded after taking a move in.
class GanBufferResult {
  /// Moves now known to be contiguous, oldest first.
  final List<BufferedMove> evicted;

  /// Set when moves are missing and the cube should be asked for them.
  final ({int serial, int count})? historyRequest;

  /// Set when the gap can no longer be recovered.
  final bool desynced;
  final int lostMoves;

  const GanBufferResult({
    this.evicted = const [],
    this.historyRequest,
    this.desynced = false,
    this.lostMoves = 0,
  });
}

/// Reorders Gen3/Gen4 moves and detects gaps.
///
/// Those generations send one move per packet with no redundancy, so a dropped
/// notification leaves a hole that only the cube's move history can fill. Moves
/// queue here until they are contiguous; a gap asks for history and holds
/// everything behind it, so the tracked model only ever sees moves in order.
///
/// Ported from `afedotov/gan-web-bluetooth` (MIT).
class GanMoveBuffer {
  /// Upstream disconnects the cube when the buffer runs away like this; the
  /// trainer would rather re-anchor and carry on.
  static const int _overflowLimit = 16;

  final List<BufferedMove> _buffer = [];

  /// Serial of the last move handed on to the model.
  int lastSerial = -1;

  /// The newest serial the cube has mentioned, move or facelets.
  int serial = -1;

  bool get needsAnchor => lastSerial == -1;

  int get length => _buffer.length;

  void reset() {
    _buffer.clear();
    lastSerial = -1;
    serial = -1;
  }

  /// Anchor tracking at [atSerial] (from the cube's own facelets).
  void anchor(int atSerial) {
    _buffer.clear();
    lastSerial = atSerial;
    serial = atSerial;
  }

  /// Take in a live move and drain whatever is now contiguous.
  GanBufferResult push(BufferedMove move) {
    serial = move.serial;
    if (needsAnchor) return const GanBufferResult();
    _buffer.add(move);
    return _evict(canRequestHistory: true);
  }

  /// Inject a move recovered from the cube's history, then drain.
  GanBufferResult injectHistory(BufferedMove move) {
    if (needsAnchor) return const GanBufferResult();
    _inject(move);
    // No history request here: this *is* the answer to one, and asking again on
    // a still-short reply would spin.
    return _evict(canRequestHistory: false);
  }

  /// A periodic facelets event at [atSerial] reveals moves we never saw when it
  /// runs ahead of the model. Returns a history request to fill the gap.
  ({int serial, int count})? checkForMissedMoves(int atSerial) {
    serial = atSerial;
    if (needsAnchor) return null;
    // Signed, so a snapshot that is *behind* the model reads as -1 rather than
    // 255: a facelets packet overtaken in flight by a move must not be mistaken
    // for the cube being a whole serial cycle ahead.
    final diff = signedSerialDiff(atSerial, lastSerial);
    // Serial 0 is skipped: the firmware reports a bogus facelets state as the
    // move counter wraps past 255.
    if (diff <= 0 || atSerial == 0) return null;
    final startSerial =
        _buffer.isNotEmpty ? _buffer.first.serial : (atSerial + 1) & 0xFF;
    return (serial: startSerial, count: diff + 1);
  }

  void _inject(BufferedMove move) {
    if (_buffer.isNotEmpty) {
      final head = _buffer.first;
      if (_buffer.any((m) => m.serial == move.serial)) return; // already held
      // Only a move that belongs in the hole between the model and the queue.
      if (!_isSerialInRange(lastSerial, head.serial, move.serial)) return;
      // History arrives newest-first, so each one lands on the head in turn.
      if (move.serial == ((head.serial - 1) & 0xFF)) {
        _buffer.insert(0, move);
      }
    } else if (_isSerialInRange(lastSerial, serial, move.serial,
        closedEnd: true)) {
      // A move recovered from a periodic facelets check, with nothing queued.
      _buffer.insert(0, move);
    }
  }

  GanBufferResult _evict({required bool canRequestHistory}) {
    final evicted = <BufferedMove>[];
    ({int serial, int count})? request;
    while (_buffer.isNotEmpty) {
      final head = _buffer.first;
      final diff = needsAnchor ? 1 : (head.serial - lastSerial) & 0xFF;
      if (diff > 1) {
        // A hole: hold the queue until the cube fills it.
        if (canRequestHistory) request = (serial: head.serial, count: diff);
        break;
      }
      _buffer.removeAt(0);
      lastSerial = head.serial;
      evicted.add(head);
    }
    if (_buffer.length > _overflowLimit) {
      final lost = _buffer.length;
      reset();
      return GanBufferResult(evicted: evicted, desynced: true, lostMoves: lost);
    }
    return GanBufferResult(evicted: evicted, historyRequest: request);
  }

  /// How far [a] is ahead of [b] on the mod-256 serial ring, as a signed value
  /// in [-128, 127]. Negative means [a] is behind.
  static int signedSerialDiff(int a, int b) => ((a - b + 128) & 0xFF) - 128;

  /// Whether the circular (mod 256) [value] falls in the open range
  /// ([start], [end]).
  static bool _isSerialInRange(int start, int end, int value,
      {bool closedStart = false, bool closedEnd = false}) {
    return ((end - start) & 0xFF) >= ((value - start) & 0xFF) &&
        (closedStart || ((start - value) & 0xFF) > 0) &&
        (closedEnd || ((end - value) & 0xFF) > 0);
  }
}
