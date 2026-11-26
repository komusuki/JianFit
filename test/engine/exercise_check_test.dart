// Tests for lib/engine/exercise_check.dart. Owner: Member C.
//   dart test test/engine/exercise_check_test.dart

import 'package:test/test.dart';
import 'package:jianfit/engine/exercise_check.dart';
import 'package:jianfit/engine/exercise_config.dart';
import 'package:jianfit/engine/geometry.dart';
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

  // fix/lying-down-banner: on the phone, lying down hides the legs, so frames
  // stop being judged and the sources send posture-only frames (main null),
  // sometimes with no lean at all.
  group('frames the engine could not judge', () {
    test('posture-only frames still show the lying message after 3 s', () {
      final check = ExerciseCheck(squatConfig);
      expect(feed(check, from: 0, to: 2900, lean: 85), isNull);
      expect(feed(check, from: 3000, to: 3000, lean: 85), lyingMessage);
    });

    test('a frame without a lean keeps the lying timer', () {
      final check = ExerciseCheck(squatConfig);
      expect(feed(check, from: 0, to: 1500, lean: 85), isNull);
      expect(feed(check, from: 1600, to: 2400, lean: double.nan), isNull);
      expect(feed(check, from: 2500, to: 3000, lean: 85), lyingMessage);
    });

    test('posture-only frames never give the no-movement message', () {
      final check = ExerciseCheck(squatConfig);
      expect(feed(check, from: 0, to: 15000, lean: 10), isNull);
    });

    test('a plank lean of about 90 never shows a message', () {
      final check = ExerciseCheck(plankConfig);
      expect(feed(check, from: 0, to: 6000, lean: 90), isNull);
      expect(feed(check, from: 6100, to: 8000, lean: double.nan), isNull);
      expect(feed(check, from: 8100, to: 15000, lean: 88), isNull);
    });
  });

  group('torsoLean', () {
    /// Shoulder and hip on both sides. Upright: shoulder straight above the
    /// hip (lean 0). Lying: shoulder beside the hip (lean 90).
    Map<int, Pt> body({
      bool lying = false,
      double leftC = 0.9,
      double rightC = 0.9,
    }) {
      final shoulder = lying ? (300.0, 100.0) : (100.0, 100.0);
      final hip = lying ? (100.0, 100.0) : (100.0, 300.0);
      return {
        for (final side in Side.values) ...{
          landmarkIndex(Joint.shoulder, side): Pt(
            shoulder.$1,
            shoulder.$2,
            side == Side.left ? leftC : rightC,
          ),
          landmarkIndex(Joint.hip, side): Pt(
            hip.$1,
            hip.$2,
            side == Side.left ? leftC : rightC,
          ),
        },
      };
    }

    test('uses the chosen side', () {
      expect(torsoLean(body(), Side.left), closeTo(0, 0.01));
      expect(torsoLean(body(lying: true), Side.right), closeTo(90, 0.01));
    });

    test('uses the other side when the chosen side is hidden', () {
      expect(
        torsoLean(body(lying: true, leftC: 0.2), Side.left),
        closeTo(90, 0.01),
      );
    });

    test('after a pause (no side) uses whichever side is visible', () {
      expect(torsoLean(body(lying: true, leftC: 0.2), null), closeTo(90, 0.01));
    });

    test('NaN when neither side is visible', () {
      expect(torsoLean(body(leftC: 0.2, rightC: 0.2), Side.left), isNaN);
      expect(torsoLean(const {}, null), isNaN);
    });
  });
}
