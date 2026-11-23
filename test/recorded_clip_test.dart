// Rep counter tests from a recorded clip (roadmap: engine tests). Owner:
// Member C. A real pose CSV from assets/replays/ goes through the full engine
// (ReplayRunner) and is checked against the hand labels in JianFit_Labels and
// tools/replay_check.py on the same clip.
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

void main() {
  const clip = 'forward-lunge_S01_side_correct_01.csv';

  test('forward lunge correct clip: 15 reps, as labeled', () {
    final runner = runClip('forward_lunge', clip);
    // Labels: 15 correct reps from 4 to 62 s. replay_check.py: detected 15.
    expect(runner.counter.count, 15);
    expect(runner.reps.length, 15);
  });

  test('forward lunge correct clip: each rep credited to the front leg', () {
    final runner = runClip('forward_lunge', clip);
    // replay_check.py: left leg in front for reps 1 to 7, right for 8 to 15.
    expect(runner.reps.map((r) => r.$1.leg).toList(), [
      for (var i = 0; i < 7; i++) Side.left,
      for (var i = 0; i < 8; i++) Side.right,
    ]);
  });
}
