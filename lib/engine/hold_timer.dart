// Hold timer (roadmap Part 5, Day 9): for hold exercises such as the plank.
// Stages: Not in Position, Holding (timer runs), Broken (timer pauses, cue).
//   In position: torso_lean at least holdMinLeanDeg (body near horizontal),
//     when the exercise measures torso_lean. Standing up is not a broken hold.
//   Holding: every form check passes on the frame; time between judged frames
//     is added, except across gaps longer than smoothResetMs.
//   Broken: a check has failed for holdBreakMs. update() returns the verdict
//     once per break, for the cue manager. The timer stops as soon as a check
//     fails, so the grace period only delays the cue, never adds time.
//   Getting into position: before the first passing frame, a hold cannot
//     break until the user has been in position for holdSettleMs (v0.5.2).

import '../models/exercise_definition.dart';
import '../models/strictness.dart';
import 'constants.dart';
import 'form_judge.dart';

enum HoldState { notInPosition, holding, broken }

class HoldTimer {
  HoldTimer(this.checks, this.strictness);

  final List<FormCheck> checks;
  final Strictness strictness;

  HoldState state = HoldState.notInPosition;

  /// Seconds held so far in this set.
  double seconds = 0;

  int? _lastPassMs; // the previous frame, if every check passed on it
  int? _failingSinceMs;
  int? _inPositionSinceMs; // first frame of this stretch in position

  /// Feed one judged frame's smoothed values. Returns the verdict when the
  /// hold breaks (once per break), otherwise null.
  RepVerdict? update(Map<String, double> values, int tMs) {
    final lastPass = _lastPassMs;
    _lastPassMs = null;
    final lean = values['torso_lean'];
    if (lean != null && lean < holdMinLeanDeg) {
      state = HoldState.notInPosition;
      _failingSinceMs = null;
      _inPositionSinceMs = null;
      return null;
    }
    final inSince = _inPositionSinceMs ??= tMs;
    final verdict = judgeValues(values, checks, strictness);
    if (verdict.correct) {
      // Only time between two passing frames counts.
      if (lastPass != null && tMs - lastPass <= smoothResetMs) {
        seconds += (tMs - lastPass) / 1000;
      }
      _lastPassMs = tMs;
      state = HoldState.holding;
      _failingSinceMs = null;
      return null;
    }
    // Still getting into position: no break yet.
    if (state == HoldState.notInPosition && tMs - inSince < holdSettleMs) {
      return null;
    }
    final since = _failingSinceMs ??= tMs;
    if (state != HoldState.broken && tMs - since >= holdBreakMs) {
      state = HoldState.broken;
      return verdict;
    }
    return null;
  }

  /// New set: time and stage start over.
  void reset() {
    state = HoldState.notInPosition;
    seconds = 0;
    _lastPassMs = null;
    _failingSinceMs = null;
    _inPositionSinceMs = null;
  }
}
