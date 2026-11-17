// Hold timer (Day 9). Run with: dart test test/engine

import 'package:test/test.dart';
import 'package:jianfit/engine/form_judge.dart';
import 'package:jianfit/engine/hold_timer.dart';
import 'package:jianfit/models/exercise_definition.dart';
import 'package:jianfit/models/strictness.dart';

FormCheck check(
  String name,
  CheckCategory category,
  LimitKind kind,
  Map<Strictness, double> limits,
) => FormCheck(
  name: name,
  category: category,
  measurement: 'hip_sag',
  timing: CheckWhen.bottom,
  kind: kind,
  limits: limits,
  cue: name,
  priority: 1,
);

final checks = [
  check('hips_sagging', CheckCategory.safety, LimitKind.max, const {
    Strictness.beginner: 15,
    Strictness.standard: 15,
    Strictness.strict: 15,
  }),
  check('hips_too_high', CheckCategory.cleanliness, LimitKind.min, const {
    Strictness.beginner: -15,
    Strictness.standard: -10,
    Strictness.strict: -6,
  }),
];

/// A plank frame (torso near horizontal) with this hip_sag.
Map<String, double> plank(double sag) => {'hip_sag': sag, 'torso_lean': 85};

void main() {
  late HoldTimer timer;
  setUp(() => timer = HoldTimer(checks, Strictness.standard));

  test('holding counts the time between passing frames', () {
    for (var t = 0; t <= 1000; t += 100) {
      expect(timer.update(plank(2), t), isNull);
    }
    expect(timer.state, HoldState.holding);
    expect(timer.seconds, closeTo(1.0, 1e-9));
  });

  test('standing up is not in position: no time, no cue', () {
    for (var t = 0; t <= 1000; t += 100) {
      expect(timer.update({'hip_sag': 0, 'torso_lean': 10}, t), isNull);
    }
    expect(timer.state, HoldState.notInPosition);
    expect(timer.seconds, 0);
  });

  test('a short failure pauses the timer but does not break the hold', () {
    for (var t = 0; t <= 500; t += 100) {
      timer.update(plank(2), t);
    }
    for (var t = 600; t <= 900; t += 100) {
      expect(timer.update(plank(20), t), isNull); // 300 ms of sagging
    }
    for (var t = 1000; t <= 1500; t += 100) {
      timer.update(plank(2), t);
    }
    expect(timer.state, HoldState.holding);
    expect(timer.seconds, closeTo(1.0, 1e-9)); // 0.5 + 0.5, not the 0.4 gap
  });

  test('failing for 500 ms breaks the hold once, with the verdict', () {
    for (var t = 0; t <= 200; t += 100) {
      timer.update(plank(2), t);
    }
    final broke = <int>[];
    for (var t = 300; t <= 1000; t += 100) {
      final v = timer.update(plank(20), t);
      if (v != null) {
        broke.add(t);
        expect(v.topFailed!.name, 'hips_sagging');
      }
    }
    expect(broke, [800]); // failing since 300
    expect(timer.state, HoldState.broken);
    timer.update(plank(2), 1100);
    timer.update(plank(2), 1200);
    expect(timer.state, HoldState.holding);
    expect(timer.seconds, closeTo(0.3, 1e-9));
  });

  test('strictness changes cleanliness limits only', () {
    final strict = HoldTimer(checks, Strictness.strict);
    for (var t = 0; t <= 600; t += 100) {
      timer.update(plank(-8), t); // standard: -10 is the limit, passes
      strict.update(plank(-8), t); // strict: -6, fails
    }
    expect(timer.state, HoldState.holding);
    expect(strict.state, HoldState.broken);
  });

  test('gaps longer than 500 ms are not counted', () {
    timer.update(plank(2), 0);
    timer.update(plank(2), 100);
    timer.update(plank(2), 900); // 800 ms without a judged frame
    timer.update(plank(2), 1000);
    expect(timer.seconds, closeTo(0.2, 1e-9));
  });

  test('reset starts a new set', () {
    for (var t = 0; t <= 500; t += 100) {
      timer.update(plank(2), t);
    }
    timer.reset();
    expect(timer.seconds, 0);
    expect(timer.state, HoldState.notInPosition);
  });

  test('judgeValues reads the current value; a missing one is skipped', () {
    final v = judgeValues({'torso_lean': 85}, checks, Strictness.standard);
    expect(v.correct, isTrue);
    expect(v.skipped.length, 2);
  });
}
