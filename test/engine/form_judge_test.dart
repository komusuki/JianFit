// Form judge (Days 6 to 7). Run with: dart test test/engine

import 'package:test/test.dart';
import 'package:jianfit/engine/form_judge.dart';
import 'package:jianfit/engine/rep_counter.dart';
import 'package:jianfit/models/exercise_definition.dart';
import 'package:jianfit/models/strictness.dart';

const depth = FormCheck(
  name: 'depth',
  category: CheckCategory.range,
  measurement: 'knee_angle',
  timing: CheckWhen.bottom,
  kind: LimitKind.max,
  limits: {
    Strictness.beginner: 100,
    Strictness.standard: 100,
    Strictness.strict: 100,
  },
  cue: 'Go lower.',
  priority: 2,
);

const torsoLean = FormCheck(
  name: 'torso_lean',
  category: CheckCategory.cleanliness,
  measurement: 'torso_lean',
  timing: CheckWhen.bottom,
  kind: LimitKind.max,
  limits: {
    Strictness.beginner: 50,
    Strictness.standard: 45,
    Strictness.strict: 40,
  },
  cue: 'Keep your chest up.',
  priority: 3,
);

const heelsDown = FormCheck(
  name: 'heels_down',
  category: CheckCategory.cleanliness,
  measurement: 'heel_lift',
  timing: CheckWhen.throughout,
  kind: LimitKind.max,
  limits: {
    Strictness.beginner: 0.08,
    Strictness.standard: 0.05,
    Strictness.strict: 0.03,
  },
  cue: 'Keep your heels down.',
  priority: 4,
);

const kneesOut = FormCheck(
  name: 'knee_safety',
  category: CheckCategory.safety,
  measurement: 'hip_angle',
  timing: CheckWhen.bottom,
  kind: LimitKind.min,
  limits: {
    Strictness.beginner: 40,
    Strictness.standard: 40,
    Strictness.strict: 40,
  },
  cue: 'Stop and reset.',
  priority: 9,
);

const checks = [depth, torsoLean, heelsDown];

RepResult rep({
  double knee = 90,
  double lean = 30,
  double hip = 80,
  double heelMax = 0.01,
  bool heelTracked = true,
}) => RepResult(
  deepest: knee,
  atDeepest: {'knee_angle': knee, 'torso_lean': lean, 'hip_angle': hip},
  durationMs: 1500,
  endMs: 3000,
  minDuring: {'knee_angle': knee, if (heelTracked) 'heel_lift': 0.0},
  maxDuring: {'knee_angle': 175, if (heelTracked) 'heel_lift': heelMax},
);

void main() {
  test('a rep that passes every check is correct', () {
    final v = judgeRep(rep(), checks, Strictness.standard);
    expect(v.correct, isTrue);
    expect(v.failed, isEmpty);
    expect(v.topFailed, isNull);
  });

  test('a failed range check makes the rep attempted', () {
    final v = judgeRep(rep(knee: 120), checks, Strictness.standard);
    expect(v.correct, isFalse);
    expect(v.failed, [depth]);
    expect(v.topFailed!.cue, 'Go lower.');
  });

  test('a failed cleanliness check makes the rep attempted', () {
    final v = judgeRep(rep(lean: 48), checks, Strictness.standard);
    expect(v.failed, [torsoLean]);
  });

  test('a failed safety check makes the rep attempted', () {
    final v = judgeRep(rep(hip: 30), [
      ...checks,
      kneesOut,
    ], Strictness.standard);
    expect(v.failed, [kneesOut]);
  });

  test('strictness changes the result of a cleanliness check', () {
    final r = rep(lean: 42); // limits: 50, 45, 40
    expect(judgeRep(r, checks, Strictness.beginner).correct, isTrue);
    expect(judgeRep(r, checks, Strictness.standard).correct, isTrue);
    expect(judgeRep(r, checks, Strictness.strict).correct, isFalse);
  });

  test('strictness does not change a range check', () {
    final r = rep(knee: 105);
    for (final s in Strictness.values) {
      expect(judgeRep(r, [depth], s).correct, isFalse);
    }
  });

  test('"throughout" uses the worst value during the rep', () {
    // At the bottom the heel could be down, but it lifted 0.07 at some point.
    final v = judgeRep(rep(heelMax: 0.07), checks, Strictness.standard);
    expect(v.failed, [heelsDown]);
  });

  test('a measurement with no value is skipped, not failed', () {
    final v = judgeRep(rep(heelTracked: false), checks, Strictness.standard);
    expect(v.correct, isTrue);
    expect(v.skipped, [heelsDown]);
  });

  test('top cue: safety first, then the lowest priority number', () {
    final v = judgeRep(rep(knee: 120, lean: 60, hip: 30), [
      ...checks,
      kneesOut,
    ], Strictness.standard);
    expect(v.failed.length, 3);
    expect(v.topFailed, kneesOut); // safety, even with priority 9
    final noSafety = judgeRep(
      rep(knee: 120, lean: 60),
      checks,
      Strictness.standard,
    );
    expect(noSafety.topFailed, depth); // priority 2 beats 3
  });

  test('a value exactly at the limit passes', () {
    expect(
      judgeRep(rep(knee: 100), [depth], Strictness.standard).correct,
      isTrue,
    );
    expect(
      judgeRep(rep(hip: 40), [kneesOut], Strictness.standard).correct,
      isTrue,
    );
  });
}
