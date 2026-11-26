// Checks the exercise file format (lib/models/exercise_definition.dart) and
// every real file in assets/exercises/. Run with: dart test test/engine

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:jianfit/engine/landmarks.dart';
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
    // heels_down removed Nov 26 for the pilot: on a second person ML Kit's
    // heel point moved by -0.3 to +1.3 body lengths, far more than a real
    // heel raise, so good squats failed it. heel_lift is still logged.
    expect(d.formChecks.map((c) => c.name), ['shallow_depth', 'forward_lean']);

    final depth = d.formChecks[0];
    expect(depth.category, CheckCategory.range);
    expect(depth.timing, CheckWhen.bottom);
    expect(depth.kind, LimitKind.max);
    expect(depth.limitFor(Strictness.beginner), 100);
    expect(depth.limitFor(Strictness.strict), 100);

    final lean = d.formChecks[1];
    expect(lean.limitFor(Strictness.beginner), 55);
    expect(lean.limitFor(Strictness.standard), 50);
    expect(lean.limitFor(Strictness.strict), 45);

  });

  test('heel_rise needs heel_lift in the measurements', () {
    final j = squatJson();
    (j['form_checks'] as List).add({
      'name': 'heels_down',
      'category': 'cleanliness',
      'measurement': 'heel_rise',
      'when': 'bottom',
      'max': {'beginner': 0.04, 'standard': 0.035, 'strict': 0.03},
      'cue': 'Keep your heels down.',
      'priority': 4,
    });
    (j['tracking']['measurements'] as List).remove('heel_lift');
    expect(
      problemsIn(j, 'bodyweight_squat.json').join('\n'),
      contains("'heel_rise'"),
    );
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

  // Day 9: holds, jump_limit and body_line_end.
  group('Day 9 fields', () {
    Map<String, dynamic> file(String name) =>
        jsonDecode(File('assets/exercises/$name').readAsStringSync())
            as Map<String, dynamic>;

    test('the jump squat file reads correctly', () {
      final d = ExerciseDefinition.fromJson(
        file('jump_squat.json'),
        'jump_squat.json',
      );
      expect(d.config.jumpLimit, 0.10);
      expect(d.config.bothSidesJoints, [Joint.ankle]);
      expect(d.formChecks.map((c) => c.name), [
        'stiff_landing',
        'shallow_depth',
        'no_jump',
      ]);
      expect(d.formChecks.first.category, CheckCategory.safety);
      expect(d.formChecks.first.measurement, 'landing_knee_min');
    });

    test('the forearm plank file is a hold with no rep fields', () {
      final d = ExerciseDefinition.fromJson(
        file('forearm_plank.json'),
        'forearm_plank.json',
      );
      expect(d.info.type, ExerciseType.hold);
      expect(d.config.mainMeasurement, isNull);
      expect(d.config.direction, isNull);
      expect(d.config.bodyLineEnd, Joint.ankle);
      expect(d.formChecks.length, 3);
    });

    test('a hold with rep fields is reported', () {
      final j = file('forearm_plank.json');
      j['tracking']['start_threshold'] = 150;
      expect(
        problemsIn(j, 'forearm_plank.json').join('\n'),
        contains('start_threshold is not used by hold exercises'),
      );
    });

    test('jump_limit needs both jump_rise measurements', () {
      final j = file('jump_squat.json');
      (j['tracking']['measurements'] as List).remove('jump_rise_right');
      expect(
        problemsIn(j, 'jump_squat.json').join('\n'),
        contains('jump_limit needs jump_rise_left and jump_rise_right'),
      );
    });

    test('jump_height and landing_knee_min need jump_limit', () {
      final j = file('jump_squat.json');
      (j['tracking'] as Map).remove('jump_limit');
      final problems = problemsIn(j, 'jump_squat.json').join('\n');
      expect(problems, contains("'jump_height'"));
      expect(problems, contains("'landing_knee_min'"));
    });

    test('body_line_end must be ankle or knee', () {
      final j = file('forearm_plank.json');
      j['tracking']['body_line_end'] = 'wrist';
      expect(
        problemsIn(j, 'forearm_plank.json').join('\n'),
        contains('body_line_end must be ankle or knee'),
      );
    });
  });
}
