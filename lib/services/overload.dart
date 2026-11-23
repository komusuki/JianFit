// Too-many-reps (overload) warning (roadmap Part 12, Days 12 to 13).
// Owner: Member C. A set ends on its own when correct reps reach the target,
// so the way to overdo it is a set that never ends: reps keep failing and the
// person keeps going. Holds have no reps, so this never applies to them.

/// Attempts past the target that trigger the warning.
const extraAttemptsLimit = 5;

/// During a set: a warning once [attempted] reaches [target] plus
/// [extraAttemptsLimit] while [correct] is still below [target], or null.
String? warnTooManyReps({
  required int attempted,
  required int correct,
  required int target,
}) {
  if (target <= 0 || correct >= target) return null;
  if (attempted < target + extraAttemptsLimit) return null;
  return 'That\'s $attempted reps for a target of $target. Take a break or '
      'lower your target.';
}
