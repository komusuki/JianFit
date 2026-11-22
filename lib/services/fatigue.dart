// Fatigue warnings (roadmap Part 12, Days 12 to 13). Owner: Member C.
// Three rules from the build guide, each against the start of the workout:
//   - 3 failed reps in a row (checked during a set),
//   - correct reps more than 30 points below the first set,
//   - reps taking more than 50% longer than the first reps.
// Holds (the plank) have no reps, so none of these apply to them.

import '../models/workout_records.dart';

/// Failed reps in a row that trigger a warning during a set.
const failedInARow = 3;

/// Drop in the share of correct reps, compared with the first set.
const accuracyDropLimit = 0.30;

/// How much slower reps may get than the first reps (0.5 = 50%).
const slowdownLimit = 0.50;

/// How many reps at the start of the workout set the normal rep time.
const baselineReps = 3;

/// During a set: a warning after [failedStreak] failed reps in a row, or null.
String? warnDuringSet(int failedStreak) => failedStreak >= failedInARow
    ? '$failedStreak reps in a row didn\'t count. Slow down and check your '
          'form, or take a short break.'
    : null;

/// After a set ends: a warning comparing it with the start of the workout,
/// or null. [sets] holds every finished set, the one that just ended last.
String? warnAfterSet(List<SetRecord> sets) {
  if (sets.length < 2) return null;
  final first = sets.first, last = sets.last;
  if (first.reps.isEmpty || last.reps.isEmpty) return null;

  final firstRate = first.correctReps / first.attemptedReps;
  final lastRate = last.correctReps / last.attemptedReps;
  if (firstRate - lastRate > accuracyDropLimit) {
    return 'Your form is slipping: ${_pct(lastRate)} of reps counted this '
        'set, ${_pct(firstRate)} in set 1. Rest longer or lower your target.';
  }

  final start = _meanMs(first.reps.take(baselineReps));
  final now = _meanMs(last.reps);
  if (start > 0 && now > start * (1 + slowdownLimit)) {
    return 'Your reps are getting slow: ${_sec(now)} each, ${_sec(start)} at '
        'the start. You may be tired, so rest longer or stop here.';
  }
  return null;
}

double _meanMs(Iterable<RepRecord> reps) {
  final list = reps.toList();
  if (list.isEmpty) return 0;
  return list.fold<int>(0, (sum, r) => sum + r.durationMs) / list.length;
}

String _pct(double rate) => '${(rate * 100).round()}%';

String _sec(double ms) => '${(ms / 1000).toStringAsFixed(1)} s';
