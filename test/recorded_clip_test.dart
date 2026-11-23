// Rep counter tests from recorded clips (roadmap: engine tests). Owner:
// Member C. Real pose CSVs from assets/replays/ go through the full engine
// (ReplayRunner) and are checked against the hand labels in JianFit_Labels and
// tools/replay_check.py on the same clips (strictness standard).
// Run with: flutter test test/recorded_clip_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:jianfit/engine/landmarks.dart';
import 'package:jianfit/models/exercise_definition.dart';
import 'package:jianfit/models/strictness.dart';
import 'package:jianfit/services/replay_runner.dart';
import 'package:jianfit/services/replay_source.dart';
import 'package:test/test.dart';

/// Runs a whole clip from assets/replays/ through [exerciseId]'s real file.
ReplayRunner runClip(String exerciseId, String clip) {
  final json = jsonDecode(
    File('assets/exercises/$exerciseId.json').readAsStringSync(),
  );
  final exercise = ExerciseDefinition.fromJson(json, '$exerciseId.json');
  final frames = parseReplayCsv(
    File('assets/replays/$clip').readAsStringSync(),
  );
  return ReplayRunner(exercise, Strictness.standard)..runAll(frames);
}

/// Rep numbers (from 1) whose verdict is not correct.
List<int> flaggedReps(ReplayRunner runner) => [
  for (var i = 0; i < runner.reps.length; i++)
    if (!runner.reps[i].$2.correct) i + 1,
];

void main() {
  group('forward lunge, forward-lunge_S01_side_correct_01', () {
    final runner = runClip(
      'forward_lunge',
      'forward-lunge_S01_side_correct_01.csv',
    );

    test('15 reps, as labeled', () {
      // Labels: 15 correct reps from 4 to 62 s. replay_check.py: detected 15.
      expect(runner.counter.count, 15);
      expect(runner.reps.length, 15);
    });

    test('each rep credited to the front leg', () {
      // replay_check.py: left leg in front for reps 1 to 7, right for 8 to 15.
      expect(runner.reps.map((r) => r.$1.leg).toList(), [
        for (var i = 0; i < 7; i++) Side.left,
        for (var i = 0; i < 8; i++) Side.right,
      ]);
    });

    test('same form verdicts as replay_check.py', () {
      // Reps 5 and 6: back_knee_high just over 0.6. Rep 8: tracking glitch.
      expect(flaggedReps(runner), [5, 6, 8]);
    });
  });

  group('reverse lunge, reverse-lunge_S01_side_correct_01', () {
    final runner = runClip(
      'reverse_lunge',
      'reverse-lunge_S01_side_correct_01.csv',
    );

    test('12 reps, as labeled', () {
      expect(runner.counter.count, 12);
      expect(runner.reps.length, 12);
    });

    test('each rep credited to the front leg', () {
      // replay_check.py: right leg in front for reps 1 to 6, left for 7 to 12.
      expect(runner.reps.map((r) => r.$1.leg).toList(), [
        for (var i = 0; i < 6; i++) Side.right,
        for (var i = 0; i < 6; i++) Side.left,
      ]);
    });

    test('every rep judged correct', () {
      expect(flaggedReps(runner), isEmpty);
    });
  });

  group('bodyweight squat, bodyweight-squat_S01_side_correct_01', () {
    final runner = runClip(
      'bodyweight_squat',
      'bodyweight-squat_S01_side_correct_01.csv',
    );

    test('12 reps, as labeled', () {
      expect(runner.counter.count, 12);
      expect(runner.reps.length, 12);
    });

    test('every rep judged correct', () {
      expect(flaggedReps(runner), isEmpty);
    });
  });
}
