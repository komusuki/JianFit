import 'package:test/test.dart';
import 'package:jianfit/engine/exercise_config.dart';
import 'package:jianfit/engine/geometry.dart';
import 'package:jianfit/engine/landmarks.dart';
import 'package:jianfit/engine/measurement_layer.dart';

import 'squat_config.dart';

/// A person standing straight, facing right. Left side is more confident.
Map<int, Pt> standingFrame() {
  final m = <int, Pt>{};
  void put(Joint j, double x, double y) {
    m[landmarkIndex(j, Side.left)] = Pt(x, y, 0.9);
    m[landmarkIndex(j, Side.right)] = Pt(x, y, 0.6);
  }

  put(Joint.ear, 110, 40);
  put(Joint.shoulder, 100, 100);
  put(Joint.hip, 100, 300);
  put(Joint.knee, 100, 500);
  put(Joint.ankle, 100, 700);
  put(Joint.heel, 90, 710);
  put(Joint.footIndex, 130, 710);
  return m;
}

/// standingFrame() moved by dx and dy pixels.
Map<int, Pt> shifted(double dx, double dy) => {
  for (final e in standingFrame().entries)
    e.key: Pt(e.value.x + dx, e.value.y + dy, e.value.c),
};

const lungeLike = ExerciseConfig(
  id: 'test_lunge',
  posture: Posture.standing,
  requiredJoints: [Joint.shoulder, Joint.hip],
  bothSidesJoints: [Joint.hip, Joint.knee, Joint.ankle],
  measurements: ['torso_lean'],
  mainMeasurement: 'torso_lean',
  direction: Direction.dip,
  startThreshold: 150,
  completeThreshold: 160,
);

void main() {
  test('setup picks side, facing and baseline, then judges frames', () {
    final layer = MeasurementLayer(squatConfig);
    for (var t = 0; t < 1000; t += 100) {
      expect(layer.process(standingFrame(), t).status, FrameStatus.setup);
    }
    expect(layer.process(standingFrame(), 1000).status, FrameStatus.setup);
    expect(layer.side, Side.left);
    expect(layer.facing, 1);
    expect(layer.baseline['heel_left'], 710);
    expect(layer.baseline['floor'], 710);

    final f = layer.process(standingFrame(), 1100);
    expect(f.status, FrameStatus.judged);
    expect(f.values['knee_angle'], closeTo(180, 0.01));
    expect(f.values['hip_angle'], closeTo(180, 0.01));
    expect(f.values['torso_lean'], closeTo(0, 0.01));
    expect(f.values['heel_lift'], closeTo(0, 0.01));
  });

  test('pauses after 2000 ms without a judgeable frame', () {
    final layer = MeasurementLayer(squatConfig);
    for (var t = 0; t <= 1000; t += 100) {
      layer.process(standingFrame(), t);
    }
    expect(layer.process(standingFrame(), 1100).status, FrameStatus.judged);
    expect(layer.process(const {}, 2000).status, FrameStatus.skipped);
    expect(layer.process(const {}, 3100).status, FrameStatus.paused);
    expect(layer.isReady, isFalse);
  });

  test('setup ignores weak detections (for example a chair)', () {
    final layer = MeasurementLayer(squatConfig);
    final weak = {
      for (final e in standingFrame().entries)
        e.key: Pt(e.value.x, e.value.y, 0.2),
    };
    for (var t = 0; t <= 2000; t += 100) {
      layer.process(weak, t);
    }
    expect(layer.isReady, isFalse);
  });

  test('side by pass rate beats higher mean confidence (formula v0.4)', () {
    // Left: confidence 1.0 and 0.45 in turn (mean 0.725, passes half the
    // frames). Right: always 0.7 (mean 0.7, passes every frame).
    Map<int, Pt> frame(double leftC) {
      final m = <int, Pt>{};
      void put(Joint j, double x, double y) {
        m[landmarkIndex(j, Side.left)] = Pt(x, y, leftC);
        m[landmarkIndex(j, Side.right)] = Pt(x, y, 0.7);
      }

      put(Joint.ear, 110, 40);
      put(Joint.shoulder, 100, 100);
      put(Joint.hip, 100, 300);
      put(Joint.knee, 100, 500);
      put(Joint.ankle, 100, 700);
      put(Joint.heel, 90, 710);
      put(Joint.footIndex, 130, 710);
      return m;
    }

    final layer = MeasurementLayer(squatConfig);
    for (var t = 0; t <= 1000; t += 100) {
      layer.process(frame(t % 200 == 0 ? 1.0 : 0.45), t);
    }
    expect(layer.side, Side.right);
  });

  test('setup stores the thigh and shin lengths of the chosen side', () {
    final layer = MeasurementLayer(squatConfig);
    for (var t = 0; t <= 1000; t += 100) {
      layer.process(standingFrame(), t);
    }
    final lengths = layer.setupSegments.map((s) => s.length).toList();
    expect(lengths, [200, 200]); // hip-knee and knee-ankle, left side
  });

  test('an impossible joint angle makes the frame unjudgeable (v0.4)', () {
    final layer = MeasurementLayer(squatConfig);
    for (var t = 0; t <= 1000; t += 100) {
      layer.process(standingFrame(), t);
    }
    final bad = Map.of(standingFrame());
    // Ankle folded back up beside the hip: knee angle about 6 degrees, with
    // the shin still a plausible length (about 191 px vs 200 px at setup).
    bad[landmarkIndex(Joint.ankle, Side.left)] = const Pt(80, 310, 0.9);
    expect(layer.process(bad, 1100).status, FrameStatus.skipped);
    // A normal frame right after is judged again.
    expect(layer.process(standingFrame(), 1200).status, FrameStatus.judged);
  });

  test('a thigh or shin far from its setup length is unjudgeable (v0.4)', () {
    final layer = MeasurementLayer(squatConfig);
    for (var t = 0; t <= 1000; t += 100) {
      layer.process(standingFrame(), t);
    }
    final bad = Map.of(standingFrame());
    // Shin 400 px instead of 200 px: knee angle is still 180 (straight).
    bad[landmarkIndex(Joint.ankle, Side.left)] = const Pt(100, 900, 0.9);
    expect(layer.process(bad, 1100).status, FrameStatus.skipped);
  });

  test('implausible frames count toward the automatic pause', () {
    final layer = MeasurementLayer(squatConfig);
    for (var t = 0; t <= 1000; t += 100) {
      layer.process(standingFrame(), t);
    }
    final bad = Map.of(standingFrame());
    bad[landmarkIndex(Joint.ankle, Side.left)] = const Pt(100, 900, 0.9);
    expect(layer.process(bad, 2000).status, FrameStatus.skipped);
    expect(layer.process(bad, 3000).status, FrameStatus.paused);
  });

  test('both-sides joints must pass on both sides (lunges)', () {
    final layer = MeasurementLayer(lungeLike);
    final hiddenFarLeg = Map.of(standingFrame());
    hiddenFarLeg[landmarkIndex(Joint.knee, Side.right)] = const Pt(
      100,
      500,
      0.3,
    );
    expect(layer.hasPerson(standingFrame()), isTrue);
    expect(layer.hasPerson(hiddenFarLeg), isFalse);
  });

  test('a person needs a head: no ear means no person (v0.5, chair)', () {
    final layer = MeasurementLayer(squatConfig);
    final noHead = Map.of(standingFrame())
      ..remove(landmarkIndex(Joint.ear, Side.left))
      ..remove(landmarkIndex(Joint.ear, Side.right));
    expect(layer.hasPerson(noHead), isFalse);
    for (var t = 0; t <= 2000; t += 100) {
      layer.process(noHead, t);
    }
    expect(layer.isReady, isFalse);

    // One ear is enough (the far ear is often hidden in side view).
    final oneEar = Map.of(standingFrame())
      ..remove(landmarkIndex(Joint.ear, Side.right));
    expect(layer.hasPerson(oneEar), isTrue);
  });

  test('setup waits until the person stands still (v0.5)', () {
    final layer = MeasurementLayer(squatConfig);
    // Walking into place: 30 px per frame, more than 0.1 x 200 px.
    for (var t = 0; t < 1000; t += 100) {
      layer.process(shifted(0, t * 0.3), t);
    }
    expect(layer.isReady, isFalse);
    // Then standing still 300 px lower from 1000 ms.
    for (var t = 1000; t < 2000; t += 100) {
      layer.process(shifted(0, 300), t);
    }
    expect(layer.isReady, isFalse);
    layer.process(shifted(0, 300), 2000);
    expect(layer.isReady, isTrue);
    expect(layer.baseline['heel_left'], 1010); // the still position
  });

  test('small jitter does not restart setup (v0.5)', () {
    final layer = MeasurementLayer(squatConfig);
    for (var t = 0; t <= 1000; t += 100) {
      layer.process(shifted(t % 200 == 0 ? 5 : -5, 0), t);
    }
    expect(layer.isReady, isTrue);
  });

  test('both-sides exercises skip the stillness check (v0.4.1)', () {
    final layer = MeasurementLayer(lungeLike);
    for (var t = 0; t <= 1000; t += 100) {
      layer.process(shifted(t * 0.3, 0), t);
    }
    expect(layer.isReady, isTrue);
  });
}
