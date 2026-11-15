// Tests for lib/services/database_service.dart. Owner: Member C.
// Runs on the laptop with an in-memory database (sqflite_common_ffi):
//   flutter test test/database_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:jianfit/models/workout_records.dart';
import 'package:jianfit/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late DatabaseService service;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    service = DatabaseService(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
  });

  tearDown(() => service.close());

  RepRecord rep(int n, {List<String> fails = const []}) => RepRecord(
    repNumber: n,
    correct: fails.isEmpty,
    durationMs: 1800,
    depth: 80,
    failedChecks: [for (final f in fails) FailedCheck(name: f, category: 'range', value: 1)],
  );

  test('saves a session and reads back its summary', () async {
    final id = await service.saveSession(
      SessionRecord(
        startedAt: DateTime(2026, 11, 15, 9),
        mode: 'single',
        strictness: 'standard',
        sets: [
          SetRecord(exerciseId: 'reverse_lunge', setNumber: 1, targetReps: 3, reps: [
            rep(1),
            rep(2, fails: ['torso_lean']),
            rep(3),
          ]),
          SetRecord(exerciseId: 'reverse_lunge', setNumber: 2, targetReps: 3, reps: [
            rep(1, fails: ['torso_lean', 'knee_past_ankle']),
            rep(2, fails: ['torso_lean']),
            rep(3),
          ]),
        ],
      ),
    );

    final s = (await service.getSummary(id))!;
    expect(s.correctReps, 3);
    expect(s.attemptedReps, 6);
    expect(s.formAccuracy, closeTo(0.5, 1e-9));
    expect(s.topMistake, 'torso_lean');
    expect(s.topMistakeCount, 3);
    expect(s.sets.map((x) => [x.setNumber, x.correctReps, x.attemptedReps]).toList(), [
      [1, 2, 3],
      [2, 1, 3],
    ]);
  });

  test('summary of a hold-only session has no accuracy and no mistake', () async {
    final id = await service.saveSession(
      SessionRecord(
        startedAt: DateTime(2026, 11, 15, 9),
        mode: 'single',
        strictness: 'beginner',
        sets: const [
          SetRecord(exerciseId: 'forearm_plank', setNumber: 1, targetSeconds: 30, holdSeconds: 28.5),
        ],
      ),
    );
    final s = (await service.getSummary(id))!;
    expect(s.attemptedReps, 0);
    expect(s.formAccuracy, isNull);
    expect(s.topMistake, isNull);
    expect(s.sets.single.holdSeconds, 28.5);
  });

  test('unknown session id gives no summary', () async {
    expect(await service.getSummary(999), isNull);
  });

  test('history lists sessions newest first with totals', () async {
    for (final day in [10, 14, 12]) {
      await service.saveSession(
        SessionRecord(
          startedAt: DateTime(2026, 11, day),
          mode: 'single',
          strictness: 'standard',
          sets: [
            SetRecord(exerciseId: 'bodyweight_squat', setNumber: 1, reps: [
              rep(1),
              rep(2, fails: ['heel_lift']),
            ]),
          ],
        ),
      );
    }
    final list = await service.listSessions();
    expect(list.map((x) => x.startedAt.day).toList(), [14, 12, 10]);
    expect(list.first.correctReps, 1);
    expect(list.first.attemptedReps, 2);
    expect(list.first.exerciseIds, ['bodyweight_squat']);
  });

  test('deleting a session removes its sets, reps and checks', () async {
    final id = await service.saveSession(
      SessionRecord(
        startedAt: DateTime(2026, 11, 15),
        mode: 'single',
        strictness: 'standard',
        sets: [
          SetRecord(exerciseId: 'forward_lunge', setNumber: 1, reps: [rep(1, fails: ['torso_lean'])]),
        ],
      ),
    );
    await service.deleteSession(id);
    final db = await service.database;
    for (final table in ['sessions', 'sets', 'reps', 'failed_checks']) {
      final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
      expect(rows.first['n'], 0, reason: table);
    }
  });

  test('routines keep their items in order', () async {
    await service.saveRoutine(
      const Routine(
        name: 'Test routine',
        items: [
          RoutineItem(exerciseId: 'reverse_lunge', targetReps: 8, sets: 2, restSec: 45),
          RoutineItem(exerciseId: 'forearm_plank', targetSeconds: 30, sets: 1, restSec: 60),
          RoutineItem(exerciseId: 'bodyweight_squat', targetReps: 10, sets: 3, restSec: 60),
        ],
      ),
    );
    final routines = await service.listRoutines();
    expect(routines.single.name, 'Test routine');
    expect(routines.single.items.map((i) => i.exerciseId).toList(), [
      'reverse_lunge',
      'forearm_plank',
      'bodyweight_squat',
    ]);
    expect(routines.single.items[1].targetSeconds, 30);
  });

  test('fake data: 3 sessions with the expected summaries, added only once', () async {
    final now = DateTime(2026, 11, 15, 12);
    expect(await service.seedFakeData(now: now), isTrue);
    expect(await service.seedFakeData(now: now), isFalse);

    final list = await service.listSessions();
    expect(list.length, 3);
    expect(list.map((x) => [x.correctReps, x.attemptedReps]).toList(), [
      [9, 12], // yesterday: reverse lunge, strict
      [14, 16], // 2 days ago: leg day routine (plank has no reps)
      [16, 20], // 3 days ago: squats
    ]);

    final legDay = (await service.getSummary(list[1].id))!;
    expect(legDay.sets.length, 3);
    expect(legDay.topMistake, 'back_knee_high'); // 3 checks tied at 1: alphabetical
    final squats = (await service.getSummary(list[2].id))!;
    expect(squats.topMistake, 'heel_lift');
    expect(squats.topMistakeCount, 3);
    expect((await service.listRoutines()).single.items.length, 3);
  });
}
