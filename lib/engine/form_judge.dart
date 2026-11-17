// Form judge (roadmap Part 7, Days 6 to 7): when a rep completes, run every
// form check from the exercise file.
//   range: one standard target. cleanliness: the user's strictness level.
//   safety: one fixed limit.
// All checks pass: correct rep. Any fails: attempted only.
// Keep tools/replay_check.py judging the same way.

import '../models/exercise_definition.dart';
import '../models/strictness.dart';
import 'rep_counter.dart';

/// One check's outcome for one rep.
class CheckResult {
  const CheckResult(this.check, this.value, this.limit);

  final FormCheck check;

  /// The value the check read, or null if that measurement had no judgeable
  /// value during the rep (for example the heel was not tracked).
  final double? value;

  /// The limit used, for the chosen strictness level.
  final double limit;

  /// Null when skipped (no value).
  bool? get passed {
    final v = value;
    if (v == null) return null;
    return check.kind == LimitKind.max ? v <= limit : v >= limit;
  }
}

class RepVerdict {
  const RepVerdict(this.results);

  final List<CheckResult> results;

  List<FormCheck> get failed => [
    for (final r in results)
      if (r.passed == false) r.check,
  ];

  /// Checks that could not be judged this rep. They don't fail the rep.
  List<FormCheck> get skipped => [
    for (final r in results)
      if (r.passed == null) r.check,
  ];

  bool get correct => failed.isEmpty;

  /// The most important failed check: safety first, then the lowest priority
  /// number, then the order in the file. Null when the rep is correct.
  FormCheck? get topFailed {
    FormCheck? best;
    for (final c in failed) {
      if (best == null || _beats(c, best)) best = c;
    }
    return best;
  }

  static bool _beats(FormCheck a, FormCheck b) {
    final aSafety = a.category == CheckCategory.safety;
    final bSafety = b.category == CheckCategory.safety;
    if (aSafety != bSafety) return aSafety;
    return a.priority < b.priority;
  }
}

/// The value a check reads from the rep: the deepest frame for "bottom";
/// the worst value during the rep for "throughout".
double? checkValue(FormCheck check, RepResult rep) => switch (check.timing) {
  CheckWhen.bottom => rep.atDeepest[check.measurement],
  CheckWhen.throughout =>
    check.kind == LimitKind.max
        ? rep.maxDuring[check.measurement]
        : rep.minDuring[check.measurement],
};

/// Judges one completed rep against [checks] at the given strictness level.
RepVerdict judgeRep(
  RepResult rep,
  List<FormCheck> checks,
  Strictness strictness,
) => RepVerdict([
  for (final c in checks)
    CheckResult(c, checkValue(c, rep), c.limitFor(strictness)),
]);

/// Judges one frame's values (holds such as the plank): every check reads the
/// current smoothed value, whatever its "when".
RepVerdict judgeValues(
  Map<String, double> values,
  List<FormCheck> checks,
  Strictness strictness,
) => RepVerdict([
  for (final c in checks)
    CheckResult(c, values[c.measurement], c.limitFor(strictness)),
]);
