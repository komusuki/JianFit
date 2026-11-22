// Tests for lib/engine/exercise_check.dart. Owner: Member C.
//   dart test test/engine/exercise_check_test.dart

import 'package:test/test.dart';
import 'package:jianfit/engine/exercise_check.dart';
import 'package:jianfit/engine/exercise_config.dart';
import 'package:jianfit/engine/landmarks.dart';

import 'squat_config.dart';

const plankConfig = ExerciseConfig(
  id: 'forearm_plank',
  posture: Posture.floor,
  requiredJoints: [Joint.shoulder, Joint.elbow, Joint.hip, Joint.ankle],
  measurements: ['hip_sag', 'elbow_under_shoulder', 'torso_lean'],
);

/// Frames every 100 ms from [from] to [to]; returns the last message.
String? feed(
  ExerciseCheck check, {
  required int from,
  required int to,
  double lean = 10,
  double? Function(int t)? main,
}) {
  String? last;
  for (var t = from; t <= to; t += 100) {
    last = check.update(lean: lean, main: main?.call(t), tMs: t);
  }
  return last;
}

void main() {
  group('posture', () {
    test('lying down for 3 s during a standing exercise', () {
      final check = ExerciseCheck(squatConfig);
      expect(feed(check, from: 0, to: 2900, lean: 85, main: (_) => 170), isNull);
      expect(feed(check, from: 3000, to: 3000, lean: 85, main: (_) => 170),
          lyingMessage);
    });

    test('a deep squat lean (60 degrees) is not lying down', () {
      final check = ExerciseCheck(squatConfig);
      expect(feed(check, from: 0, to: 5000, lean: 60, main: (t) => t % 2000 < 1000 ? 90 : 170),
          isNull);
    });

    test('upright for 5 s during a floor exercise', () {
      final check = ExerciseCheck(plankConfig);
      expect(feed(check, from: 0, to: 4900, lean: 5), isNull);
      expect(feed(check, from: 5000, to: 5000, lean: 5), uprightMessage);
    });

    test('getting back into position clears it', () {
      final check = ExerciseCheck(plankConfig);
      feed(check, from: 0, to: 6000, lean: 5);
      expect(feed(check, from: 6100, to: 6100, lean: 85), isNull);
    });
  });

  group('no movement', () {
    test('10 s with the knee angle barely changing', () {
      final check = ExerciseCheck(squatConfig);
      expect(feed(check, from: 0, to: 9900, main: (t) => 170 + (t % 300) / 100),
          isNull);
      expect(feed(check, from: 10000, to: 10000, main: (_) => 171), stillMessage);
    });

    test('moving more than 15 degrees starts the wait again', () {
      final check = ExerciseCheck(squatConfig);
      feed(check, from: 0, to: 8000, main: (_) => 170);
      feed(check, from: 8100, to: 8100, main: (_) => 140); // bends down
      expect(feed(check, from: 8200, to: 15000, main: (_) => 140), isNull);
    });

    test('a finished rep starts the wait again', () {
      final check = ExerciseCheck(squatConfig);
      feed(check, from: 0, to: 9000, main: (_) => 170);
      check.update(lean: 10, main: 170, tMs: 9100, repDone: true);
      expect(feed(check, from: 9200, to: 15000, main: (_) => 170), isNull);
    });

    test('holds never get the no-movement message', () {
      final check = ExerciseCheck(plankConfig);
      expect(feed(check, from: 0, to: 30000, lean: 85), isNull);
    });

    test('reset starts over', () {
      final check = ExerciseCheck(squatConfig);
      feed(check, from: 0, to: 9900, main: (_) => 170);
      check.reset();
      expect(feed(check, from: 10000, to: 15000, main: (_) => 170), isNull);
    });
  });
}
