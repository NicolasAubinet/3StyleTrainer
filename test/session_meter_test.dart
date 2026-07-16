import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/screens/session_summary_screen.dart';

// The Sets row meter. The target tick sits at 65% of the track: under-target
// times stop short of it, over-target ones run past it toward a full bar.
const double tick = 0.65;
const double floor = 0.05;

void main() {
  // Convenience: a session whose slowest case is [slowest] seconds.
  double frac(double seconds, {required double target, double? slowest}) =>
      meterFrac((seconds * 1000).round(),
          targetMs: target * 1000,
          slowestMs: ((slowest ?? seconds) * 1000).round());

  group('under target: absolute, so it reads against the target itself', () {
    test('the reported case: a lone 2.76s against a 3s target is nearly there',
        () {
      // Was 5% — the session-relative scale pinned the only time to the floor,
      // reading as if it were miles under target instead of 8% under.
      expect(frac(2.76, target: 3.0), closeTo(0.598, 0.001));
    });

    test('fill is proportional to the target, tick at 100% of it', () {
      expect(frac(1.5, target: 3.0), closeTo(tick * 0.5, 0.001));
      expect(frac(2.25, target: 3.0), closeTo(tick * 0.75, 0.001));
      expect(frac(2.97, target: 3.0), closeTo(tick * 0.99, 0.001));
    });

    test('a very fast case keeps the visibility floor', () {
      expect(frac(0.1, target: 3.0), floor); // 0.65 * 0.033 would vanish
      expect(frac(0.001, target: 3.0), floor);
    });

    test('the session fastest no longer pins to the floor', () {
      // Same 2.99s case, in sessions with wildly different fastest times. It is
      // the fastest in the first and the slowest in the last; the bar is the
      // same either way, because standing is the colour's job, not the bar's.
      for (final slowest in [2.99, 3.5, 9.0]) {
        expect(frac(2.99, target: 3.0, slowest: slowest),
            closeTo(tick * 0.9967, 0.001),
            reason: 'slowest=$slowest');
      }
    });

    test('a tight session is not exaggerated across the whole track', () {
      // 2.70/2.80/2.90 used to spread 5%/25%/45% — a huge visual range for
      // times within 7% of each other.
      final f = [for (final t in [2.7, 2.8, 2.9]) frac(t, target: 3.0, slowest: 2.9)];
      expect(f.first, closeTo(0.585, 0.001));
      expect(f.last, closeTo(0.628, 0.001));
      expect(f.last - f.first, lessThan(0.05));
    });
  });

  group('over target: session-relative, so one bad case cannot peg the rest',
      () {
    test('a case at the target sits exactly on the tick', () {
      expect(frac(3.0, target: 3.0, slowest: 9.0), tick);
    });

    test('the session slowest fills the track', () {
      expect(frac(9.0, target: 3.0, slowest: 9.0), 1.0);
    });

    test('slower cases spread between the tick and the slowest', () {
      // The bug 22524d1 fixed: with an absolute scale everything past ~1.5x the
      // target pegged, so a whole run read as uniformly full. It must not come
      // back — these are all >1.5x target and must stay distinct.
      final f = [for (final t in [5.0, 6.0, 7.0, 9.0]) frac(t, target: 3.0, slowest: 9.0)];
      for (var i = 1; i < f.length; i++) {
        expect(f[i], greaterThan(f[i - 1]), reason: 'must not peg: $f');
      }
      expect(f.last, 1.0);
    });
  });

  group('a single time carries real signal', () {
    // It used to be binary: 5% under target, 100% over, whatever the time.
    test('a lone case just over target barely passes the tick', () {
      expect(frac(3.01, target: 3.0), closeTo(0.652, 0.001));
    });

    test('a lone case a hair over target reads nothing like a disastrous one',
        () {
      expect(frac(9.0, target: 3.0) - frac(3.01, target: 3.0),
          greaterThan(0.3));
    });

    test('a lone under-target time is ordered by how near the target it is', () {
      final near = frac(2.9, target: 3.0);
      final mid = frac(1.5, target: 3.0);
      final far = frac(0.5, target: 3.0);
      expect(near, greaterThan(mid));
      expect(mid, greaterThan(far));
    });

    test('1.5x the target fills the track when nothing is slower', () {
      expect(frac(4.5, target: 3.0), 1.0);
      expect(frac(4.4, target: 3.0), lessThan(1.0));
    });
  });

  group('edges', () {
    test('no target falls back to the tick', () {
      expect(meterFrac(2760, targetMs: 0, slowestMs: 2760), tick);
      expect(meterFrac(2760, targetMs: -1, slowestMs: 2760), tick);
    });

    test('every result stays on the track', () {
      for (final t in [0, 1, 500, 2999, 3000, 3001, 60000]) {
        for (final slowest in [0, 1, 3000, 60000]) {
          final f = meterFrac(t, targetMs: 3000, slowestMs: slowest);
          expect(f, inInclusiveRange(0.0, 1.0), reason: 't=$t slowest=$slowest');
        }
      }
    });

    test('a slowest below the target cannot invert the scale', () {
      // slowestMs < targetMs is reachable: the target is editable on the
      // summary itself, so it can be raised above every recorded time.
      final f = meterFrac(3000, targetMs: 3000, slowestMs: 1000);
      expect(f, tick);
    });
  });
}
