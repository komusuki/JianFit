// Tests for lib/services/fatigue.dart. Owner: Member C.
//   flutter test test/fatigue_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:jianfit/models/workout_records.dart';
import 'package:jianfit/services/fatigue.dart';

/// A set of [results] reps (true = correct), each taking [ms] milliseconds.
SetRecord set(int number, List<bool> results, {int ms = 2000}) => SetRecord(
  exerciseId: 'bodyweight_squat',
  setNumber: number,
  targetReps: 6,
  reps: [
    for (var i = 0; i < results.length; i++)
      RepRecord(repNumber: i + 1, correct: results[i], durationMs: ms),
  ],
);

void main() {
  group('during a set', () {
    test('2 failed reps in a row: no warning', () {
      expect(warnDuringSet(2), isNull);
    });

    test('3 failed reps in a row: warning', () {
      expect(warnDuringSet(3), contains("3 reps in a row didn't count"));
    });
  });

  group('after a set', () {
    test('the first set never warns', () {
      expect(warnAfterSet([set(1, [false, false, false, true])]), isNull);
    });

    test('correct reps fall more than 30 points: warning', () {
      final warning = warnAfterSet([
        set(1, [true, true, true, true, true, true]), // 100%
        set(2, [true, true, true, false, false, true, false, false]), // 50%
      ]);
      expect(warning, contains('50% of reps counted this set, 100% in set 1'));
    });

    test('a smaller drop (25 points): no warning', () {
      expect(
        warnAfterSet([
          set(1, [true, true, true, true]), // 100%
          set(2, [true, true, true, false]), // 75%
        ]),
        isNull,
      );
    });

    test('reps more than 50% slower than the first reps: warning', () {
      final warning = warnAfterSet([
        set(1, [true, true, true, true], ms: 2000),
        set(2, [true, true, true, true], ms: 3200),
      ]);
      expect(warning, contains('3.2 s each, 2.0 s at the start'));
    });

    test('reps exactly 50% slower: no warning', () {
      expect(
        warnAfterSet([
          set(1, [true, true, true], ms: 2000),
          set(2, [true, true, true], ms: 3000),
        ]),
        isNull,
      );
    });

    test('a plank set (no reps) never warns', () {
      expect(
        warnAfterSet(const [
          SetRecord(exerciseId: 'forearm_plank', setNumber: 1, holdSeconds: 30),
          SetRecord(exerciseId: 'forearm_plank', setNumber: 2, holdSeconds: 12),
        ]),
        isNull,
      );
    });
  });
}
