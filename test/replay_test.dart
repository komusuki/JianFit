// Replay mode (Day 7). Owner: Member C.
// Run with: flutter test test/replay_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:jianfit/models/exercise_definition.dart';
import 'package:jianfit/models/strictness.dart';
import 'package:jianfit/services/replay_runner.dart';
import 'package:jianfit/services/replay_source.dart';
import 'package:test/test.dart';

String header() => [
  'frame,t_ms,width,height',
  for (var k = 0; k < 33; k++) 'lm${k}_x,lm${k}_y,lm${k}_c',
].join(',');

String row(int frame, String tMs, {bool person = true}) => [
  '$frame,$tMs,640,480',
  for (var k = 0; k < 33; k++) person ? '${k + 0.5},${k * 2},0.9' : ',,',
].join(',');

void main() {
  test('parses a replay CSV, including a row with no person', () {
    final frames = parseReplayCsv(
      '${header()}\n${row(0, '0')}\r\n${row(4, '66.7', person: false)}\n',
    );
    expect(frames.length, 2);
    expect(frames[0].points.length, 33);
    expect(frames[0].points[11]!.x, 11.5);
    expect(frames[0].points[11]!.y, 22);
    expect(frames[0].points[11]!.c, 0.9);
    expect(frames[1].frame, 4);
    expect(frames[1].tMs, 67);
    expect(frames[1].points, isEmpty);
    expect(frames[1].width, 640);
  });

  test('a CSV without the replay columns is rejected', () {
    expect(() => parseReplayCsv('frame,x,y\n1,2,3'), throwsFormatException);
  });

  test('the exercise id comes from the file name', () {
    expect(
      exerciseIdFromReplayName(
        'assets/replays/reverse-lunge_S01_side_correct_01.csv',
      ),
      'reverse_lunge',
    );
    expect(
      exerciseIdFromReplayName('knee-push-up_S02_side_01.csv'),
      'knee_push_up',
    );
    expect(
      exerciseIdFromReplayName('bodyweight-squat_S01_side_01.csv'),
      'bodyweight_squat',
    );
  });

  test('same reps as tools/replay_check.py on the synthetic squat clip', () {
    final json = jsonDecode(
      File('assets/exercises/bodyweight_squat.json').readAsStringSync(),
    );
    final squat = ExerciseDefinition.fromJson(json, 'bodyweight_squat.json');
    final frames = parseReplayCsv(
      File('test/fixtures/replay_squat.csv').readAsStringSync(),
    );
    final runner = ReplayRunner(squat, Strictness.standard)..runAll(frames);
    // replay_check.py on the same clip: 3 reps, deepest 90.5 each,
    // ending at about 3.40, 5.60 and 7.30 s.
    expect(runner.counter.count, 3);
    for (final (rep, _) in runner.reps) {
      expect(rep.deepest, closeTo(90.5, 0.5));
    }
    expect(runner.reps.map((r) => r.$1.endMs / 1000).toList(), [
      closeTo(3.40, 0.05),
      closeTo(5.60, 0.05),
      closeTo(7.30, 0.05),
    ]);
  });

  test('before the set begins, setup runs but no reps are counted', () {
    final json = jsonDecode(
      File('assets/exercises/bodyweight_squat.json').readAsStringSync(),
    );
    final squat = ExerciseDefinition.fromJson(json, 'bodyweight_squat.json');
    final frames = parseReplayCsv(
      File('test/fixtures/replay_squat.csv').readAsStringSync(),
    );
    final runner = ReplayRunner(squat, Strictness.standard);
    for (final f in frames) {
      runner.step(f, countReps: false);
    }
    expect(runner.layer.isReady, isTrue);
    expect(runner.counter.count, 0);
    expect(runner.reps, isEmpty);
  });
}
