// Tests for lib/services/rep_records.dart. Owner: Member C.
//   flutter test test/rep_records_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianfit/engine/form_judge.dart';
import 'package:jianfit/engine/landmarks.dart';
import 'package:jianfit/engine/rep_counter.dart';
import 'package:jianfit/models/exercise_definition.dart';
import 'package:jianfit/models/strictness.dart';
import 'package:jianfit/services/rep_records.dart';

void main() {
  // The forward lunge's real checks: knee_past_ankle 0.37, shallow_front_knee
  // 90, back_knee_high 0.6, torso_lean 18.
  final lunge = ExerciseDefinition.fromJson(
    jsonDecode(File('assets/exercises/forward_lunge.json').readAsStringSync()),
    'forward_lunge.json',
  );

  RepResult rep(double knee, {Side? leg}) => RepResult(
    deepest: knee,
    atDeepest: {
      'front_knee_angle': knee,
      'back_knee_height': 0.3,
      'front_knee_over_ankle': 0.2,
      'torso_lean': 5,
    },
    durationMs: 1800,
    endMs: 6200,
    leg: leg,
  );

  test('a failed rep keeps each failed check with its value', () {
    final r = rep(95, leg: Side.right);
    final record = repRecordFrom(
      3,
      r,
      judgeRep(r, lunge.formChecks, Strictness.standard),
    );
    expect(record.repNumber, 3);
    expect(record.correct, isFalse);
    expect(record.depth, 95);
    expect(record.durationMs, 1800);
    expect(record.endedAtMs, 6200);
    expect(record.frontLeg, 'R');
    expect(record.failedChecks.map((c) => c.name), ['shallow_front_knee']);
    expect(record.failedChecks.single.category, 'range');
    expect(record.failedChecks.single.value, 95);
  });

  test('a correct rep has no failed checks', () {
    final r = rep(80);
    final record = repRecordFrom(
      1,
      r,
      judgeRep(r, lunge.formChecks, Strictness.standard),
    );
    expect(record.correct, isTrue);
    expect(record.failedChecks, isEmpty);
    expect(record.frontLeg, isNull);
  });
}
