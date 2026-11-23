import 'package:flutter/material.dart';

import '../models/exercise_definition.dart';
import '../models/exercise_info.dart';
import '../models/strictness.dart';
import '../models/workout_records.dart';
import '../services/settings_service.dart';
import '../services/workout_launcher.dart';
import '../services/workout_source.dart';
import 'setup_check_screen.dart';
import '../widgets/number_picker.dart';

class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
    this.definition,
  });

  final ExerciseInfo exercise;

  /// Member A's exercise file, or null if this exercise has no file yet.
  final ExerciseDefinition? definition;

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  late int _target = _isHold ? 30 : 10;
  int _sets = 3;
  int _restSeconds = 60;
  Strictness _strictness = Strictness.standard;
  bool _replay = false; // developer replay mode (Settings)

  bool get _isHold => widget.exercise.type == ExerciseType.hold;

  /// Replay mode, the engine or made-up data (workout_launcher.dart).
  WorkoutSource _makeSource() => makeSource(
    widget.exercise,
    widget.definition,
    _strictness,
    replay: _replay,
  );

  bool get _landscape => isLandscape(widget.exercise, widget.definition);

  @override
  void initState() {
    super.initState();
    SettingsService.loadStrictness().then((s) {
      if (mounted) setState(() => _strictness = s);
    });
    SettingsService.loadReplayMode().then((on) {
      if (mounted) setState(() => _replay = on);
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(e.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            height: 180,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_outline, size: 48),
                SizedBox(height: 8),
                Text('Demo clip coming soon'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('${e.level}, ${e.pattern}'),
          const SizedBox(height: 16),
          Text('Camera', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('${e.cameraView} view. ${e.placement}'),
          const SizedBox(height: 16),
          Text('Target', style: textTheme.titleMedium),
          NumberPicker(
            label: _isHold ? 'Seconds per set' : 'Correct reps per set',
            value: _target,
            min: _isHold ? 10 : 1,
            max: _isHold ? 300 : 50,
            step: _isHold ? 5 : 1,
            onChanged: (v) => setState(() => _target = v),
          ),
          NumberPicker(
            label: 'Sets',
            value: _sets,
            min: 1,
            max: 10,
            step: 1,
            onChanged: (v) => setState(() => _sets = v),
          ),
          NumberPicker(
            label: 'Rest between sets (seconds)',
            value: _restSeconds,
            min: 15,
            max: 180,
            step: 15,
            onChanged: (v) => setState(() => _restSeconds = v),
          ),
          const SizedBox(height: 16),
          Text('Strictness', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<Strictness>(
            segments: const [
              ButtonSegment(
                value: Strictness.beginner,
                label: Text('Beginner'),
              ),
              ButtonSegment(
                value: Strictness.standard,
                label: Text('Standard'),
              ),
              ButtonSegment(value: Strictness.strict, label: Text('Strict')),
            ],
            selected: {_strictness},
            onSelectionChanged: (s) => setState(() => _strictness = s.first),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(_replay ? 'Start (replay)' : 'Start'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SetupCheckScreen(
                  exercise: e,
                  source: _makeSource(),
                  plan: RoutineItem(
                    exerciseId: e.id,
                    targetReps: _isHold ? null : _target,
                    targetSeconds: _isHold ? _target : null,
                    sets: _sets,
                    restSec: _restSeconds,
                  ),
                  strictness: _strictness,
                  landscape: _landscape,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
