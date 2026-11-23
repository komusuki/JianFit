import 'package:flutter/material.dart';

import '../models/exercise_definition.dart';
import '../models/exercise_info.dart';
import '../models/strictness.dart';
import '../models/workout_records.dart';
import '../screens/setup_check_screen.dart';
import 'database_service.dart';
import 'engine_workout_source.dart';
import 'exercise_loader.dart';
import 'fake_workout_source.dart';
import 'replay_workout_source.dart';
import 'settings_service.dart';
import 'workout_source.dart';

// Starting workouts, shared by Today, the routine list and exercise details.

/// One exercise the app can run: its info, and Member A's file if it has one.
typedef CatalogEntry = (ExerciseInfo, ExerciseDefinition?);

/// The 8 core exercises (file if there is one, fake data if not), then any
/// file that isn't one of them. Same order as the exercise list.
Future<List<CatalogEntry>> loadCatalog() async {
  final loaded = await ExerciseLoader.loadAll();
  return [
    for (final fake in fakeExercises)
      (loaded.exercises[fake.id]?.info ?? fake, loaded.exercises[fake.id]),
    for (final def in loaded.exercises.values)
      if (!fakeExercises.any((f) => f.id == def.info.id)) (def.info, def),
  ];
}

/// Which source drives the workout: Member C's replay mode when the
/// developer switch is on, Member A's engine when the exercise has a file,
/// otherwise made-up data so every exercise can still be tried.
WorkoutSource makeSource(
  ExerciseInfo info,
  ExerciseDefinition? def,
  Strictness strictness, {
  bool replay = false,
}) {
  if (replay) return ReplayWorkoutSource(info, strictness: strictness);
  if (def != null) return EngineWorkoutSource(def, strictness);
  return FakeWorkoutSource(info);
}

/// Portrait for standing exercises, landscape for floor exercises.
/// Exercises without a file guess from their placement text.
bool isLandscape(ExerciseInfo info, ExerciseDefinition? def) {
  final o = def?.orientation;
  if (o != null) return o == 'landscape';
  return info.placement.contains('floor');
}

/// A routine in progress (Custom Workout Mode). The live screen adds each
/// exercise's sets here and hands over to the next exercise; the session is
/// saved once, at the end or on Stop.
class RoutineRun {
  RoutineRun({
    required this.routine,
    required this.catalog,
    required this.strictness,
    required this.replay,
  });

  final Routine routine;
  final Map<String, CatalogEntry> catalog;
  final Strictness strictness;
  final bool replay;
  final DateTime startedAt = DateTime.now();

  /// Sets of the exercises already finished.
  final sets = <SetRecord>[];

  /// The exercise in progress, from 0.
  int index = 0;

  RoutineItem get item => routine.items[index];
  bool get isLast => index == routine.items.length - 1;

  /// Name of the exercise after this one, or null on the last one.
  String? get nextName =>
      isLast ? null : catalog[routine.items[index + 1].exerciseId]!.$1.name;

  /// Saves the finished exercises plus [current] (the sets of the exercise
  /// in progress) as one session. Null when nothing was done or saving
  /// failed.
  Future<int?> save(List<SetRecord> current) async {
    final all = [...sets, ...current];
    final done = all.any((s) => s.reps.isNotEmpty || (s.holdSeconds ?? 0) >= 1);
    if (!done) return null;
    try {
      return await DatabaseService.instance.saveSession(
        SessionRecord(
          startedAt: startedAt,
          endedAt: DateTime.now(),
          mode: 'custom',
          routineId: routine.id,
          strictness: strictness.name,
          sets: all,
        ),
      );
    } catch (e) {
      debugPrint('Saving the routine failed: $e');
      return null;
    }
  }

  /// The setup check for the exercise in progress.
  Widget setupScreen() {
    final (info, def) = catalog[item.exerciseId]!;
    return SetupCheckScreen(
      exercise: info,
      source: makeSource(info, def, strictness, replay: replay),
      plan: item,
      strictness: strictness,
      landscape: isLandscape(info, def),
      run: this,
    );
  }
}

/// Starts a routine from its first exercise and remembers it as the last
/// used routine. Shows a message instead when the routine can't run.
Future<void> startRoutine(BuildContext context, Routine routine) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final catalog = {for (final e in await loadCatalog()) e.$1.id: e};
  final unknown = routine.items.any((i) => !catalog.containsKey(i.exerciseId));
  if (routine.items.isEmpty || unknown) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          routine.items.isEmpty
              ? 'This routine has no exercises.'
              : 'This routine uses an exercise this version does not have.',
        ),
      ),
    );
    return;
  }
  final strictness = await SettingsService.loadStrictness();
  final replay = await SettingsService.loadReplayMode();
  final id = routine.id;
  if (id != null) await SettingsService.saveLastRoutineId(id);
  final run = RoutineRun(
    routine: routine,
    catalog: catalog,
    strictness: strictness,
    replay: replay,
  );
  await navigator.push(MaterialPageRoute(builder: (_) => run.setupScreen()));
}
