// Records saved in the local database (roadmap Part 12). Owner: Member C.
//
// Exercises are stored by the engine's exercise id (for example
// 'bodyweight_squat') and strictness by its name ('beginner', 'standard',
// 'strict'), so this file does not depend on any screen code.
//
// Counting rule (roadmap Part 7): a rep where every check passes is correct;
// a rep where any check fails counts as attempted only. "Attempted" in the
// summary is every rep, so correct <= attempted.

/// One form check that failed on a rep, for example 'torso_lean'.
class FailedCheck {
  const FailedCheck({required this.name, this.category, this.value});

  /// Check name from the exercise file, for example 'knee_past_ankle'.
  final String name;

  /// 'safety', 'range' or 'cleanliness' (optional).
  final String? category;

  /// The measured value that failed (optional).
  final double? value;
}

/// One rep, as the rep counter and form judge produced it.
class RepRecord {
  const RepRecord({
    required this.repNumber,
    required this.correct,
    required this.durationMs,
    this.depth,
    this.endedAtMs,
    this.frontLeg,
    this.failedChecks = const [],
  });

  final int repNumber;
  final bool correct;

  /// Deepest value of the main measurement (RepResult.deepest).
  final double? depth;

  /// From leaving Ready to Complete (RepResult.durationMs).
  final int durationMs;

  /// Time in the set when the rep completed (RepResult.endMs).
  final int? endedAtMs;

  /// Lunges only: 'L' or 'R'.
  final String? frontLeg;

  final List<FailedCheck> failedChecks;
}

/// One set of one exercise. Holds (forearm plank) have no reps.
class SetRecord {
  const SetRecord({
    required this.exerciseId,
    required this.setNumber,
    this.targetReps,
    this.targetSeconds,
    this.holdSeconds,
    this.reps = const [],
  });

  final String exerciseId;
  final int setNumber;
  final int? targetReps;
  final int? targetSeconds;

  /// Holds only: seconds held with good form.
  final double? holdSeconds;

  final List<RepRecord> reps;

  int get correctReps => reps.where((r) => r.correct).length;
  int get attemptedReps => reps.length;
}

/// One workout from start to stop.
class SessionRecord {
  const SessionRecord({
    required this.startedAt,
    required this.mode,
    required this.strictness,
    this.endedAt,
    this.routineId,
    this.sets = const [],
  });

  final DateTime startedAt;
  final DateTime? endedAt;

  /// 'single' (Single Exercise Mode) or 'custom' (Custom Workout Mode).
  final String mode;

  /// Custom workouts only: the routine that was run.
  final int? routineId;

  /// 'beginner', 'standard' or 'strict'.
  final String strictness;

  final List<SetRecord> sets;
}

/// One row of the History list.
class SessionListItem {
  const SessionListItem({
    required this.id,
    required this.startedAt,
    required this.mode,
    required this.strictness,
    required this.correctReps,
    required this.attemptedReps,
    required this.exerciseIds,
    this.endedAt,
  });

  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String mode;
  final String strictness;
  final int correctReps;
  final int attemptedReps;
  final List<String> exerciseIds;
}

/// One line of the set breakdown in a summary.
class SetSummary {
  const SetSummary({
    required this.exerciseId,
    required this.setNumber,
    required this.correctReps,
    required this.attemptedReps,
    this.targetReps,
    this.targetSeconds,
    this.holdSeconds,
  });

  final String exerciseId;
  final int setNumber;
  final int correctReps;
  final int attemptedReps;
  final int? targetReps;
  final int? targetSeconds;
  final double? holdSeconds;
}

/// Session summary (roadmap Part 12): correct vs attempted, form accuracy,
/// most common mistake, set breakdown.
class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.correctReps,
    required this.attemptedReps,
    required this.sets,
    this.topMistake,
    this.topMistakeCount = 0,
  });

  final int sessionId;
  final int correctReps;
  final int attemptedReps;

  /// Most common failed check in the session, or null if none failed.
  final String? topMistake;
  final int topMistakeCount;

  final List<SetSummary> sets;

  /// Correct / attempted, from 0 to 1. Null when there were no reps
  /// (for example a plank-only session).
  double? get formAccuracy =>
      attemptedReps == 0 ? null : correctReps / attemptedReps;
}

/// One exercise in a saved routine (Custom Workout Mode).
class RoutineItem {
  const RoutineItem({
    required this.exerciseId,
    required this.sets,
    required this.restSec,
    this.targetReps,
    this.targetSeconds,
  });

  final String exerciseId;
  final int? targetReps;
  final int? targetSeconds;
  final int sets;

  /// Rest between sets, in seconds.
  final int restSec;
}

class Routine {
  const Routine({required this.name, this.id, this.items = const []});

  final int? id;
  final String name;

  /// In the order the user arranged them.
  final List<RoutineItem> items;
}
