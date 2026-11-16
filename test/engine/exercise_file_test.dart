// Checks the exercise file format (lib/models/exercise_definition.dart) and
// every real file in assets/exercises/. Run with: dart test test/engine

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:jianfit/models/exercise_definition.dart';
import 'package:jianfit/models/exercise_info.dart';
import 'package:jianfit/models/strictness.dart';

import 'squat_config.dart';

const squatFile = 'assets/exercises/bodyweight_squat.json';

Map<String, dynamic> squatJson() =>
    jsonDecode(File(squatFile).readAsStringSync()) as Map<String, dynamic>;

/// The problems found in [json], or an empty list if it is valid.
List<String> problemsIn(
  Object? json, [
  String fileName = 'bodyweight_squat.json',
]) {
  try {
    ExerciseDefinition.fromJson(json, fileName);
    return const [];
  } on ExerciseFileException catch (e) {
    return e.problems;
  }
}

void main() {
  test('every file in assets/exercises/ is valid', () {
    final files = Directory('assets/exercises')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'));
    expect(files, isNotEmpty);
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      expect(
        problemsIn(jsonDecode(f.readAsStringSync()), name),
        isEmpty,
        reason: name,
      );
    }
  });

  test('the squat file reads correctly', () {
    final d = ExerciseDefinition.fromJson(squatJson(), 'bodyweight_squat.json');
    expect(d.id, 'bodyweight_squat');
    expect(d.info.name, 'Bodyweight squat');
    expect(d.info.type, ExerciseType.reps);
    expect(d.info.cameraView, 'Side');
    expect(d.orientation, 'portrait');
    expect(d.oneSided, isFalse);
    // heels_down removed Nov 16 until the heel measurement is fixed (v0.6).
    expect(d.formChecks.map((c) => c.name), ['depth', 'torso_lean']);

    final depth = d.formChecks[0];
    expect(depth.category, CheckCategory.range);
    expect(depth.timing, CheckWhen.bottom);
    expect(depth.kind, LimitKind.max);
    expect(depth.limitFor(Strictness.beginner), 100);
    expect(depth.limitFor(Strictness.strict), 100);

    final lean = d.formChecks[1];
    expect(lean.limitFor(Strictness.beginner), 50);
    expect(lean.limitFor(Strictness.standard), 45);
    expect(lean.limitFor(Strictness.strict), 40);
  });

  test('the squat file matches the test settings (squat_config.dart)', () {
    final c = ExerciseDefinition.fromJson(
      squatJson(),
      'bodyweight_squat.json',
    ).config;
    expect(c.posture, squatConfig.posture);
    expect(c.requiredJoints, squatConfig.requiredJoints);
    expect(c.bothSidesJoints, squatConfig.bothSidesJoints);
    expect(c.measurements, squatConfig.measurements);
    expect(c.mainMeasurement, squatConfig.mainMeasurement);
    expect(c.direction, squatConfig.direction);
    expect(c.startThreshold, squatConfig.startThreshold);
    expect(c.completeThreshold, squatConfig.completeThreshold);
  });

  group('a broken file gives a clear message', () {
    test('unknown measurement', () {
      final j = squatJson();
      (j['tracking']['measurements'] as List)[0] = 'knee_angel';
      expect(
        problemsIn(j).join('\n'),
        contains("unknown measurement 'knee_angel'"),
      );
    });

    test('unknown joint', () {
      final j = squatJson();
      (j['tracking']['required_joints'] as List).add('elbo');
      expect(problemsIn(j).join('\n'), contains("unknown joint 'elbo'"));
    });

    test('thresholds in the wrong order', () {
      final j = squatJson();
      j['tracking']['complete_threshold'] = 140;
      expect(problemsIn(j).join('\n'), contains('must be above'));
    });

    test('cleanliness check missing a strictness level', () {
      final j = squatJson();
      (j['form_checks'][1]['max'] as Map).remove('strict');
      expect(problemsIn(j).join('\n'), contains('max.strict is missing'));
    });

    test('range check with three limits instead of one', () {
      final j = squatJson();
      j['form_checks'][0]['max'] = {'beginner': 1, 'standard': 2, 'strict': 3};
      expect(problemsIn(j).join('\n'), contains('must be one number'));
    });

    test('wrong category', () {
      final j = squatJson();
      j['form_checks'][0]['category'] = 'style';
      expect(
        problemsIn(j).join('\n'),
        contains('must be one of range, cleanliness, safety'),
      );
    });

    test('both max and min', () {
      final j = squatJson();
      j['form_checks'][0]['min'] = 60;
      expect(problemsIn(j).join('\n'), contains('exactly one of max or min'));
    });

    test('check on a measurement the exercise does not track', () {
      final j = squatJson();
      j['form_checks'][0]['measurement'] = 'elbow_angle';
      expect(
        problemsIn(j).join('\n'),
        contains('must be one of tracking.measurements'),
      );
    });

    test('id that does not match the file name', () {
      expect(
        problemsIn(squatJson(), 'jump_squat.json').join('\n'),
        contains("must match the file name (jump_squat)"),
      );
    });

    test('several problems are all reported at once', () {
      final j = squatJson();
      j.remove('name');
      j['type'] = 'repz';
      j['form_checks'][1]['priority'] = 0;
      final problems = problemsIn(j);
      expect(problems.length, 3);
    });

    test('when is optional and defaults to bottom', () {
      final j = squatJson();
      (j['form_checks'][1] as Map).remove('when');
      final d = ExerciseDefinition.fromJson(j, 'bodyweight_squat.json');
      expect(d.formChecks[1].timing, CheckWhen.bottom);
    });
  });
}
