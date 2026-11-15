import 'package:test/test.dart';
import 'package:jianfit/engine/exercise_config.dart';
import 'package:jianfit/engine/rep_counter.dart';

/// Feeds values 200 ms apart and returns the completed reps.
/// (200 ms keeps every test rep longer than minRepMs = 500.)
List<RepResult> run(RepCounter c, List<double> values) {
  final reps = <RepResult>[];
  for (var i = 0; i < values.length; i++) {
    final r = c.update(values[i], const {}, i * 200);
    if (r != null) reps.add(r);
  }
  return reps;
}

RepCounter squat() => RepCounter(
  direction: Direction.dip,
  startThreshold: 150,
  completeThreshold: 160,
);

const deepSquat = <double>[175, 160, 149, 120, 95, 90, 92, 100, 130, 158, 165];

void main() {
  test('one deep squat is one rep', () {
    final reps = run(squat(), deepSquat);
    expect(reps.length, 1);
    expect(reps.first.deepest, 90);
    expect(reps.first.durationMs, 1600);
  });

  test('three squats in a row are three reps', () {
    final c = squat();
    run(c, [...deepSquat, ...deepSquat, ...deepSquat]);
    expect(c.count, 3);
  });

  test('a shallow squat still counts (the form judge decides if correct)', () {
    final reps = run(squat(), [175, 155, 145, 148, 158, 165]);
    expect(reps.length, 1);
    expect(reps.first.deepest, 145);
  });

  test('jitter between the two thresholds is not a rep', () {
    expect(run(squat(), [175, 152, 158, 153, 157, 152, 170]), isEmpty);
  });

  test('stages: going down until it turns back by 5 degrees', () {
    final c = squat();
    run(c, [175, 149, 120, 90, 92]);
    expect(c.stage, RepStage.goingDown);
    c.update(100, const {}, 1000);
    expect(c.stage, RepStage.comingUp);
  });

  test('a rep shorter than minRepMs is dropped (formula v0.4.2)', () {
    final c = squat();
    const values = [175.0, 160.0, 140.0, 120.0, 165.0];
    for (var i = 0; i < values.length; i++) {
      // Starts at 200 ms, comes back at 400 ms: only 200 ms long.
      expect(c.update(values[i], const {}, i * 100), isNull);
    }
    expect(c.count, 0);
    expect(c.stage, RepStage.ready);
  });

  test('a rep of exactly minRepMs still counts', () {
    final c = squat();
    expect(c.update(175, const {}, 0), isNull);
    expect(c.update(140, const {}, 100), isNull); // leaves Ready
    expect(c.update(120, const {}, 300), isNull);
    expect(c.update(165, const {}, 600), isNotNull); // 500 ms long
    expect(c.count, 1);
  });

  test('hill exercise (glute bridge) counts the other way', () {
    final c = RepCounter(
      direction: Direction.hill,
      startThreshold: 150,
      completeThreshold: 140,
    );
    final reps = run(c, [120, 155, 175, 170, 150, 135]);
    expect(reps.length, 1);
    expect(reps.first.deepest, 175);
  });
}
