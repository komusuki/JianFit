// Turns the engine's rep result and verdict into the record saved in the
// database (Member C). Used by EngineWorkoutSource and ReplayWorkoutSource.

import '../engine/form_judge.dart';
import '../engine/landmarks.dart';
import '../engine/rep_counter.dart';
import '../models/workout_records.dart';

/// Rep [number] of a set, with every failed check and the value it read.
RepRecord repRecordFrom(int number, RepResult rep, RepVerdict verdict) =>
    RepRecord(
      repNumber: number,
      correct: verdict.correct,
      depth: rep.deepest,
      durationMs: rep.durationMs,
      endedAtMs: rep.endMs,
      frontLeg: switch (rep.leg) {
        Side.left => 'L',
        Side.right => 'R',
        null => null,
      },
      failedChecks: [
        for (final r in verdict.results)
          if (r.passed == false)
            FailedCheck(
              name: r.check.name,
              category: r.check.category.name,
              value: r.value,
            ),
      ],
    );
