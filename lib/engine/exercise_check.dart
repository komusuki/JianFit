// Rule-based exercise check (roadmap Part 9, Days 12 to 13). Owner: Member C,
// reviewed by Member A. Catches two things during a set:
//   - wrong posture for the chosen exercise: lying down during a standing
//     exercise, or upright during a floor one;
//   - no movement: the main measurement barely changes and no rep finishes.
// Fed every frame while the set is counting. Frames the engine can't judge
// (joints hidden, paused, setting up again) still feed the posture rule, so
// lying down shows its message even after the body stops being judged.

import 'constants.dart';
import 'exercise_config.dart';
import 'geometry.dart';
import 'landmarks.dart';

/// Torso lean (degrees from upright) above which a person counts as lying.
const lyingLeanDeg = 70.0;

/// Torso lean below which a person counts as upright.
const uprightLeanDeg = 30.0;

/// How long the wrong posture must last before the message shows. Floor
/// exercises get longer, since the person has to get down after the countdown.
const wrongPostureStandingMs = 3000;
const wrongPostureFloorMs = 5000;

/// No rep and the main measurement within this many degrees for this long.
const stillRangeDeg = 15.0;
const stillMs = 10000;

const lyingMessage =
    'You seem to be lying down. This exercise is done standing.';
const uprightMessage = 'Get down into position on the floor.';
const stillMessage =
    'No reps yet. Start when you\'re ready, with your whole body in view.';

/// Torso lean from a frame's points: on [side] when its shoulder and hip are
/// visible, else on the other side (after a pause the engine has no side).
/// NaN when neither side has both points at minConfidence or more.
double torsoLean(Map<int, Pt> points, Side? side) {
  final first = side ?? Side.left;
  final other = first == Side.left ? Side.right : Side.left;
  for (final s in [first, other]) {
    final shoulder = points[landmarkIndex(Joint.shoulder, s)];
    final hip = points[landmarkIndex(Joint.hip, s)];
    if (shoulder == null || hip == null) continue;
    if (shoulder.c < minConfidence || hip.c < minConfidence) continue;
    return lean(shoulder, hip);
  }
  return double.nan;
}

class ExerciseCheck {
  ExerciseCheck(this.config);

  final ExerciseConfig config;

  int? _wrongSince;
  int? _stillSince;
  double _stillMin = 0;
  double _stillMax = 0;

  /// One frame. [lean] is the torso lean (NaN when unknown), [main] the main
  /// measurement (null for holds and for frames the engine couldn't judge),
  /// [repDone] true on the frame a rep finished. Returns the message to show,
  /// or null.
  String? update({
    required double lean,
    double? main,
    required int tMs,
    bool repDone = false,
  }) {
    final standing = config.posture == Posture.standing;
    // A frame without a lean says nothing about posture: keep the timer, so
    // a phone that only sometimes sees the shoulder and hip still gets there.
    if (!lean.isNaN) {
      final wrong = standing ? lean > lyingLeanDeg : lean < uprightLeanDeg;
      _wrongSince = wrong ? (_wrongSince ?? tMs) : null;
    }
    final limit = standing ? wrongPostureStandingMs : wrongPostureFloorMs;
    if (_wrongSince != null && tMs - _wrongSince! >= limit) {
      return standing ? lyingMessage : uprightMessage;
    }

    if (main == null || main.isNaN) return null; // holds: no reps to wait for
    final still = _stillSince;
    if (repDone || still == null) {
      _restartStill(main, tMs);
      return null;
    }
    if (main < _stillMin) _stillMin = main;
    if (main > _stillMax) _stillMax = main;
    if (_stillMax - _stillMin > stillRangeDeg) {
      _restartStill(main, tMs);
      return null;
    }
    return tMs - still >= stillMs ? stillMessage : null;
  }

  void _restartStill(double main, int tMs) {
    _stillSince = tMs;
    _stillMin = main;
    _stillMax = main;
  }

  /// New set or a pause: start over.
  void reset() {
    _wrongSince = null;
    _stillSince = null;
  }
}
