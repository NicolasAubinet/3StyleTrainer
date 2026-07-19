import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
// ignore: implementation_imports
import 'package:smartcube/src/reconstruct/frame_algebra.dart';
import 'package:smartcube_example/trace_page.dart';

/// A cube we can push arbitrary reported moves into.
class _FakeCube implements SmartCube {
  final controller = StreamController<CubeMove>.broadcast();
  @override
  Stream<CubeMove> get moves => controller.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Simulates a physical cube: tracks the core's rotation and reports each
/// solver-frame turn in the cube's own drifted frame.
class _PhysicalCube {
  FaceRotation rho = kIdentity;

  List<(Face, bool)> slice(Slice s, int amount) {
    final dec = decomposeSlice(s, amount);
    final out = [
      for (final t in dec.sensed) (toReportedFrame(t.face, rho), t.amount == 3)
    ];
    rho = compose(dec.drift, rho);
    return out;
  }

  List<(Face, bool)> outer(Face f) => [(toReportedFrame(f, rho), false)];
}

Future<void> _feed(WidgetTester t, _FakeCube cube, List<(Face, bool)> turns) async {
  for (final (face, prime) in turns) {
    cube.controller.add(CubeMove(
      face: face,
      prime: prime,
      cubeTimestamp: Duration.zero,
    ));
    // Broadcast delivery is a microtask: one pump to deliver, one to rebuild.
    await t.pump();
    await t.pump();
  }
}

void main() {
  testWidgets('triage renders and walks the operator through every axis',
      (t) async {
    final cube = _FakeCube();
    await t.pumpWidget(MaterialApp(home: TracePage(cube)));

    // The instructions must name a concrete move, not just "do a slice".
    expect(find.textContaining('Do one slow E slice'), findsOneWidget);
    expect(find.textContaining('middle horizontal layer'), findsOneWidget);

    final phys = _PhysicalCube();
    // Step 1: an E slice, then the physical R turn it asks for.
    await _feed(t, cube, phys.slice(Slice.E, 1));
    expect(find.textContaining('turn the physical R face'), findsWidgets);
    await _feed(t, cube, phys.outer(Face.R));
    expect(find.textContaining('E: ✓ PASS'), findsOneWidget);

    // Step 2 moves on to the M axis on its own.
    expect(find.textContaining('Do one slow M slice'), findsOneWidget);
    await _feed(t, cube, phys.slice(Slice.M, 3));
    await _feed(t, cube, phys.outer(Face.U));
    expect(find.textContaining('M: ✓ PASS'), findsOneWidget);

    // Step 3: S axis.
    await _feed(t, cube, phys.slice(Slice.S, 1));
    await _feed(t, cube, phys.outer(Face.U));
    expect(find.textContaining('S: ✓ PASS'), findsOneWidget);

    expect(find.textContaining('ALL AXES PASS'), findsOneWidget);
  });

  testWidgets('triage FAILS when the cube drifts the other way', (t) async {
    final cube = _FakeCube();
    await t.pumpWidget(MaterialApp(home: TracePage(cube)));

    // A cube whose E drift is y instead of y': the probe R comes back as B,
    // not F. This is the mirrored-table case the triage exists to catch.
    final mirrored = _PhysicalCube()..rho = kIdentity;
    await _feed(t, cube, mirrored.slice(Slice.E, 1));
    mirrored.rho = kRotY; // pretend the real cube drifted the opposite way
    await _feed(t, cube, mirrored.outer(Face.R));

    expect(find.textContaining('E: ✗ FAIL'), findsOneWidget);
    expect(find.textContaining('asked for R'), findsOneWidget);
  });

  testWidgets('a non-slice pair is rejected and the step is repeatable',
      (t) async {
    final cube = _FakeCube();
    await t.pumpWidget(MaterialApp(home: TracePage(cube)));

    // U + D is two outer turns, not a slice.
    await _feed(t, cube, [(Face.U, false), (Face.D, false)]);
    expect(find.textContaining('is not a slice pair'), findsOneWidget);
    // Still on step 1, so the operator can just do it again.
    expect(find.textContaining('Do one slow E slice'), findsOneWidget);
  });

  testWidgets('capture tab explains the ground-truth workflow', (t) async {
    final cube = _FakeCube();
    await t.pumpWidget(MaterialApp(home: TracePage(cube)));
    await t.tap(find.text('Trace capture'));
    await t.pumpAndSettle();

    expect(find.textContaining('Type the alg you are about to execute'),
        findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}
