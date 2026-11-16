// Cue manager (Day 8). Run with: dart test test/engine

import 'package:test/test.dart';
import 'package:jianfit/engine/cue_manager.dart';
import 'package:jianfit/engine/form_judge.dart';
import 'package:jianfit/models/exercise_definition.dart';
import 'package:jianfit/models/strictness.dart';

FormCheck check(
  String name,
  CheckCategory category,
  String cue,
  int priority,
) => FormCheck(
  name: name,
  category: category,
  measurement: name,
  timing: CheckWhen.bottom,
  kind: LimitKind.max,
  limits: const {
    Strictness.beginner: 10,
    Strictness.standard: 10,
    Strictness.strict: 10,
  },
  cue: cue,
  priority: priority,
);

final depth = check('depth', CheckCategory.range, 'Go lower.', 2);
final lean = check('torso_lean', CheckCategory.cleanliness, 'Chest up.', 3);
final knees = check('knees', CheckCategory.safety, 'Knees out.', 9);

/// A verdict where [failing] fail and [passing] pass (limit 10, max).
RepVerdict verdict({
  List<FormCheck> failing = const [],
  List<FormCheck> passing = const [],
}) => RepVerdict([
  for (final c in failing) CheckResult(c, 20, 10),
  for (final c in passing) CheckResult(c, 5, 10),
]);

void main() {
  test('a correct rep clears the cue and says nothing', () {
    final cues = CueManager();
    final d = cues.onRep(verdict(passing: [depth, lean]), 1000);
    expect(d.text, isNull);
    expect(d.speak, isFalse);
    expect(d.tips, isEmpty);
  });

  test('a failed rep shows and speaks the top cue only', () {
    final cues = CueManager();
    final d = cues.onRep(verdict(failing: [lean, depth]), 1000);
    expect(d.text, 'Go lower.'); // priority 2 beats 3
    expect(d.speak, isTrue);
  });

  test('the same cue is not spoken again within 5 s, but still shown', () {
    final cues = CueManager();
    expect(cues.onRep(verdict(failing: [depth]), 1000).speak, isTrue);
    final again = cues.onRep(verdict(failing: [depth]), 5999);
    expect(again.text, 'Go lower.');
    expect(again.speak, isFalse);
    // 5 s after it was last spoken: spoken again.
    expect(cues.onRep(verdict(failing: [depth]), 6000).speak, isTrue);
  });

  test('a different cue is spoken right away', () {
    final cues = CueManager();
    cues.onRep(verdict(failing: [depth]), 1000);
    final d = cues.onRep(verdict(failing: [lean]), 2000);
    expect(d.text, 'Chest up.');
    expect(d.speak, isTrue);
  });

  test('safety cues beat other cues and are always spoken', () {
    final cues = CueManager();
    final first = cues.onRep(verdict(failing: [depth, knees]), 1000);
    expect(first.text, 'Knees out.');
    expect(first.speak, isTrue);
    expect(cues.onRep(verdict(failing: [knees]), 1500).speak, isTrue);
  });

  test('voice off: the cue is shown but never spoken', () {
    final cues = CueManager(voiceOn: false);
    final d = cues.onRep(verdict(failing: [knees, depth]), 1000);
    expect(d.text, 'Knees out.');
    expect(d.speak, isFalse);
    // Turning voice on later speaks at once (nothing was spoken before).
    cues.voiceOn = true;
    expect(cues.onRep(verdict(failing: [depth]), 1500).speak, isTrue);
  });

  test('the same mistake 3 times in a set reports a tip once', () {
    final cues = CueManager();
    expect(cues.onRep(verdict(failing: [depth]), 1000).tips, isEmpty);
    cues.onRep(verdict(passing: [depth]), 2000); // a correct rep between
    expect(cues.onRep(verdict(failing: [depth]), 3000).tips, isEmpty);
    expect(cues.onRep(verdict(failing: [depth]), 4000).tips, [depth]);
    expect(cues.onRep(verdict(failing: [depth]), 5000).tips, isEmpty);
  });

  test('every failed check counts, not only the one spoken', () {
    final cues = CueManager();
    for (var i = 0; i < 2; i++) {
      cues.onRep(verdict(failing: [depth, lean]), 1000 * i);
    }
    final d = cues.onRep(verdict(failing: [depth, lean]), 3000);
    expect(d.text, 'Go lower.');
    expect(d.tips, [depth, lean]);
  });

  test('reset starts a new set: counts and the repeat timer start over', () {
    final cues = CueManager();
    cues.onRep(verdict(failing: [depth]), 1000);
    cues.onRep(verdict(failing: [depth]), 2000);
    cues.reset();
    expect(cues.onRep(verdict(failing: [depth]), 2500).speak, isTrue);
    expect(cues.onRep(verdict(failing: [depth]), 3000).tips, isEmpty);
  });
}
