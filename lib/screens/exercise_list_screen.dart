import 'package:flutter/material.dart';

import '../models/exercise_definition.dart';
import '../models/exercise_info.dart';
import '../services/exercise_loader.dart';
import 'exercise_detail_screen.dart';

// Exercise list. Exercises with a file in assets/exercises/ come from
// Member A's loader; the rest use Member B's fake data until their owner
// writes the file.
class ExerciseListScreen extends StatefulWidget {
  const ExerciseListScreen({super.key});

  @override
  State<ExerciseListScreen> createState() => _ExerciseListScreenState();
}

class _ExerciseListScreenState extends State<ExerciseListScreen> {
  ExerciseLoadResult? _loaded;

  @override
  void initState() {
    super.initState();
    ExerciseLoader.loadAll().then((r) {
      if (mounted) setState(() => _loaded = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _loaded;
    if (loaded == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choose an exercise')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // The 8 core exercises first (file if there is one, fake data if not),
    // then any file that isn't one of them.
    final entries = <(ExerciseInfo, ExerciseDefinition?)>[
      for (final fake in fakeExercises)
        (loaded.exercises[fake.id]?.info ?? fake, loaded.exercises[fake.id]),
      for (final def in loaded.exercises.values)
        if (!fakeExercises.any((f) => f.id == def.info.id)) (def.info, def),
    ];
    final patterns = <String>[];
    for (final (info, _) in entries) {
      if (!patterns.contains(info.pattern)) patterns.add(info.pattern);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Choose an exercise')),
      body: ListView(
        children: [
          for (final error in loaded.errors)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(error, style: const TextStyle(color: Colors.red)),
            ),
          for (final pattern in patterns) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                pattern,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final (info, def) in entries.where(
              (x) => x.$1.pattern == pattern,
            ))
              ListTile(
                leading: Icon(
                  info.type == ExerciseType.hold ? Icons.timer : Icons.repeat,
                ),
                title: Text(info.name),
                subtitle: Text(
                  '${info.level}, '
                  '${info.type == ExerciseType.hold ? 'hold' : 'reps'}'
                  '${def == null ? ' (no exercise file yet)' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ExerciseDetailScreen(exercise: info, definition: def),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
