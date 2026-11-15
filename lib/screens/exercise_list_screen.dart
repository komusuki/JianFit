import 'package:flutter/material.dart';

import '../models/exercise_info.dart';
import 'exercise_detail_screen.dart';

class ExerciseListScreen extends StatelessWidget {
  const ExerciseListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final patterns = <String>[];
    for (final e in fakeExercises) {
      if (!patterns.contains(e.pattern)) patterns.add(e.pattern);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Choose an exercise')),
      body: ListView(
        children: [
          for (final pattern in patterns) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                pattern,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final e in fakeExercises.where((e) => e.pattern == pattern))
              ListTile(
                leading: Icon(
                  e.type == ExerciseType.hold ? Icons.timer : Icons.repeat,
                ),
                title: Text(e.name),
                subtitle: Text(
                  '${e.level}, ${e.type == ExerciseType.hold ? 'hold' : 'reps'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ExerciseDetailScreen(exercise: e)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}