import 'package:test/test.dart';
import 'package:jianfit/engine/exercise_config.dart';
import 'package:jianfit/engine/landmarks.dart';
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

  test('records the lowest and highest value of each measurement', () {
    final c = squat();
    final frames = [
      (175.0, 0.00),
      (140.0, 0.02), // leaves Ready
      (100.0, 0.06), // heel lifts at the bottom
      (130.0, 0.01),
      (165.0, 0.00), // complete
    ];
    RepResult? done;
    for (var i = 0; i < frames.length; i++) {
      final (knee, heel) = frames[i];
      done =
          c.update(knee, {'knee_angle': knee, 'heel_lift': heel}, i * 300) ??
          done;
    }
    expect(done, isNotNull);
    expect(done!.minDuring['knee_angle'], 100);
    expect(done.maxDuring['knee_angle'], 165);
    expect(done.maxDuring['heel_lift'], 0.06);
    expect(done.minDuring['heel_lift'], 0.0);
  });

  test('the next rep starts its ranges fresh', () {
    final c = squat();
    var t = 0;
    RepResult? last;
    for (final knee in [
      175.0,
      140.0,
      60.0,
      165.0,
      175.0,
      140.0,
      110.0,
      165.0,
    ]) {
      last = c.update(knee, {'knee_angle': knee}, t) ?? last;
      t += 300;
    }
    expect(c.count, 2);
    expect(last!.minDuring['knee_angle'], 110); // not 60 from the first rep
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

  // Jump squat (Day 9). Same frames as tools/test_rep_counter.py. The setup
  // baseline is off by +0.25 body lengths on purpose: the counter uses the
  // rise since the rep started, so the offset must not matter.
  group('jump squat', () {
    const offset = 0.25;
    // (knee angle, rise of the left ankle since setup); the right ankle is
    // 0.02 lower while in the air.
    const jump = <(double, double)>[
      (175.0, 0.0), (140.0, 0.0), (110.0, 0.0), (100.0, 0.0), (120.0, 0.0),
      (160.0, 0.0), (175.0, 0.05), // squat, take off
      (178.0, 0.30), (178.0, 0.45), (176.0, 0.22), // in the air
      (170.0, 0.02), (140.0, 0.0), (125.0, 0.0), (135.0, 0.0), (150.0, 0.0),
      (165.0, 0.0), (175.0, 0.0), // land, stand up
    ];

    RepCounter jumpSquat() => RepCounter(
      direction: Direction.dip,
      startThreshold: 150,
      completeThreshold: 160,
      jumpLimit: 0.15,
    );

    List<RepResult> feed(RepCounter c, List<(double, double)> frames) {
      final reps = <RepResult>[];
      for (var i = 0; i < frames.length; i++) {
        final (knee, rise) = frames[i];
        final r = c.update(knee, {
          'knee_angle': knee,
          'jump_rise_left': offset + rise,
          'jump_rise_right': rise == 0 ? offset : offset + rise - 0.02,
        }, i * 100);
        if (r != null) reps.add(r);
      }
      return reps;
    }

    test('a jump rep completes after the landing window', () {
      final c = jumpSquat();
      final reps = feed(c, jump);
      expect(c.count, 1);
      expect(reps.length, 1);
      final r = reps.first;
      expect(r.deepest, 100); // the squat, not the landing bend
      expect(r.atDeepest['jump_height'], closeTo(0.43, 1e-9)); // lower ankle
      expect(r.atDeepest['landing_knee_min'], 125); // 500 ms after landing
      expect(r.endMs, 1500); // landed at 1000, plus 500 ms
    });

    test('a squat without a jump completes after the wait', () {
      final reps = feed(jumpSquat(), const [
        (175.0, 0.0),
        (140.0, 0.0),
        (100.0, 0.0),
        (120.0, 0.0),
        (165.0, 0.0),
        (170.0, 0.0),
        (172.0, 0.0),
        (172.0, 0.0),
        (172.0, 0.0),
      ]);
      expect(reps.length, 1);
      expect(reps.first.endMs, 800); // back up at 400, plus 400 ms
      expect(reps.first.atDeepest['jump_height'], 0);
      expect(reps.first.atDeepest.containsKey('landing_knee_min'), isFalse);
    });

    test('one ankle rising is not a jump', () {
      final c = jumpSquat();
      final reps = <RepResult>[];
      const frames = [
        (175.0, 0.0),
        (140.0, 0.0),
        (100.0, 0.0),
        (165.0, 0.0),
        (175.0, 0.5),
        (175.0, 0.5),
        (175.0, 0.5),
        (175.0, 0.5),
        (175.0, 0.0),
      ];
      for (var i = 0; i < frames.length; i++) {
        final (knee, left) = frames[i];
        final r = c.update(knee, {
          'knee_angle': knee,
          'jump_rise_left': left,
          'jump_rise_right': 0,
        }, i * 100);
        if (r != null) reps.add(r);
      }
      expect(reps.length, 1);
      expect(reps.first.atDeepest['jump_height'], 0);
    });

    // (knee, left ankle rise, right ankle rise), 100 ms apart.
    List<RepResult> rawFeed(
      RepCounter c,
      List<(double, double, double)> frames,
    ) {
      final reps = <RepResult>[];
      for (var i = 0; i < frames.length; i++) {
        final (knee, left, right) = frames[i];
        final r = c.update(knee, {
          'knee_angle': knee,
          'jump_rise_left': left,
          'jump_rise_right': right,
        }, i * 100);
        if (r != null) reps.add(r);
      }
      return reps;
    }

    test('the jump is measured from the lowest ankle before takeoff', () {
      // The rep starts while the ankles still read 0.08 high (mid-motion).
      final reps = rawFeed(jumpSquat(), const [
        (175.0, 0.08, 0.08),
        (140.0, 0.08, 0.08),
        (110.0, 0.0, 0.0),
        (100.0, 0.0, 0.0),
        (160.0, 0.0, 0.0),
        (175.0, 0.20, 0.20),
        (176.0, 0.05, 0.05),
        (130.0, 0.0, 0.0),
        (140.0, 0.0, 0.0),
        (160.0, 0.0, 0.0),
        (170.0, 0.0, 0.0),
        (175.0, 0.0, 0.0),
      ]);
      expect(reps.length, 1);
      expect(reps.first.atDeepest['jump_height'], closeTo(0.20, 1e-9));
      expect(reps.first.endMs, 1100); // landed at 600, plus 500 ms
    });

    test('one ankle down counts as landing', () {
      // The far ankle keeps reading 0.16 to 0.20 after landing.
      final reps = rawFeed(jumpSquat(), const [
        (175.0, 0.0, 0.0),
        (140.0, 0.0, 0.0),
        (100.0, 0.0, 0.0),
        (160.0, 0.0, 0.0),
        (175.0, 0.30, 0.30),
        (176.0, 0.40, 0.40),
        (170.0, 0.05, 0.20),
        (130.0, 0.0, 0.18),
        (140.0, 0.0, 0.17),
        (160.0, 0.0, 0.16),
        (170.0, 0.0, 0.16),
        (175.0, 0.0, 0.16),
      ]);
      expect(reps.length, 1);
      expect(reps.first.endMs, 1100); // landed at 600, plus 500 ms
      expect(reps.first.atDeepest['landing_knee_min'], 130);
    });

    // Phone check, Nov 17: quick back-to-back jumps merged, and standing up
    // slowly after a landing was counted as an extra rep.
    RepCounter tuned() => RepCounter(
      direction: Direction.dip,
      startThreshold: 150,
      completeThreshold: 160,
      jumpLimit: 0.10,
    );

    test('back-to-back jumps are separate reps', () {
      final c = tuned();
      final reps = rawFeed(c, const [
        (175.0, 0.0, 0.0), (140.0, 0.0, 0.0), (100.0, 0.0, 0.0),
        (160.0, 0.0, 0.0), (175.0, 0.3, 0.3), (176.0, 0.4, 0.4),
        (170.0, 0.05, 0.05), (120.0, 0.0, 0.0), (100.0, 0.0, 0.0),
        (165.0, 0.0, 0.0), // land at 600, dip, push
        (175.0, 0.3, 0.3), (176.0, 0.4, 0.4), (170.0, 0.05, 0.05),
        (120.0, 0.0, 0.0), (100.0, 0.0, 0.0), (165.0, 0.0, 0.0),
        (175.0, 0.3, 0.3), (176.0, 0.4, 0.4), (170.0, 0.05, 0.05),
        (130.0, 0.0, 0.0), (140.0, 0.0, 0.0), (160.0, 0.0, 0.0),
        (170.0, 0.0, 0.0), (175.0, 0.0, 0.0),
      ]);
      expect(c.count, 3);
      expect(reps.map((r) => r.endMs), [1000, 1600, 2300]);
      expect(reps.map((r) => r.endMs - r.durationMs), [100, 1000, 1600]);
      expect(reps.map((r) => r.deepest), [100, 100, 100]);
      expect(reps[2].atDeepest['landing_knee_min'], 130);
    });

    test('standing up slowly after a landing is not a rep', () {
      final c = tuned();
      final reps = rawFeed(c, const [
        (175.0, 0.0, 0.0), (140.0, 0.0, 0.0), (100.0, 0.0, 0.0),
        (160.0, 0.0, 0.0), (175.0, 0.3, 0.3), (176.0, 0.4, 0.4),
        (170.0, 0.05, 0.05), (130.0, 0.0, 0.0), (120.0, 0.0, 0.0),
        (125.0, 0.0, 0.0), (135.0, 0.0, 0.0),
        (142.0, 0.0, 0.0), // landing window ends, knee still bent
        (148.0, 0.0, 0.0), (155.0, 0.0, 0.0), (165.0, 0.0, 0.0),
        (172.0, 0.0, 0.0), (172.0, 0.0, 0.0), (172.0, 0.0, 0.0),
        (172.0, 0.0, 0.0), (172.0, 0.0, 0.0), (172.0, 0.0, 0.0),
      ]);
      expect(c.count, 1);
      expect(reps.single.endMs, 1100);
    });

    test('a takeoff after the landing window starts a rep in the air', () {
      final c = tuned();
      final reps = rawFeed(c, const [
        (175.0, 0.0, 0.0), (140.0, 0.0, 0.0), (100.0, 0.0, 0.0),
        (160.0, 0.0, 0.0), (175.0, 0.3, 0.3), (176.0, 0.4, 0.4),
        (170.0, 0.05, 0.05), (150.0, 0.0, 0.0), (120.0, 0.0, 0.0),
        (100.0, 0.0, 0.0), (95.0, 0.0, 0.0),
        (110.0, 0.0, 0.0), // rep 1 completes at 1100, still bent
        (150.0, 0.0, 0.0), (165.0, 0.0, 0.0), (175.0, 0.3, 0.3), // takeoff
        (176.0, 0.4, 0.4), (170.0, 0.05, 0.05), // land at 1600
        (140.0, 0.0, 0.0), (150.0, 0.0, 0.0), (160.0, 0.0, 0.0),
        (170.0, 0.0, 0.0), (175.0, 0.0, 0.0),
      ]);
      expect(c.count, 2);
      expect(reps[1].endMs - reps[1].durationMs, 1100);
      expect(reps[1].endMs, 2100);
      expect(reps[1].deepest, 95); // the dip before the takeoff
      expect(reps[1].atDeepest['jump_height'], closeTo(0.4, 1e-9));
    });

    test('ankle drift in a deep landing is not a takeoff', () {
      // Phone check 2, Nov 17: in a deep landing the ankle points drifted up
      // past the limit and were taken as a second takeoff.
      final c = tuned();
      final reps = rawFeed(c, const [
        (175.0, 0.0, 0.0), (140.0, 0.0, 0.0), (100.0, 0.0, 0.0),
        (160.0, 0.0, 0.0), (175.0, 0.3, 0.3), (176.0, 0.4, 0.4),
        (170.0, 0.05, 0.05), // land at 600
        (130.0, 0.08, 0.08), (110.0, 0.12, 0.12), (100.0, 0.13, 0.13),
        (120.0, 0.08, 0.08),
        (150.0, 0.02, 0.02), // landing window ends at 1100
        (165.0, 0.0, 0.0), (175.0, 0.0, 0.0), (175.0, 0.0, 0.0),
        (175.0, 0.0, 0.0), (175.0, 0.0, 0.0),
      ]);
      expect(c.count, 1);
      expect(reps.single.endMs, 1100);
      expect(reps.single.atDeepest['landing_knee_min'], 100);
      expect(reps.single.atDeepest['jump_height'], closeTo(0.4, 1e-9));
    });
  });

  test(
    'lunges: each rep is credited to the front leg at its deepest frame',
    () {
      final c = squat();
      const frames = [
        (175.0, Side.left),
        (140.0, Side.left),
        (95.0, Side.right),
        (100.0, Side.left),
        (130.0, Side.left),
        (165.0, Side.left),
      ];
      RepResult? done;
      for (var i = 0; i < frames.length; i++) {
        final (knee, leg) = frames[i];
        done = c.update(knee, const {}, i * 200, leg: leg) ?? done;
      }
      expect(done!.leg, Side.right);
    },
  );
}
