// Session summary screen (roadmap Part 12). Owner: Member C.
// Shows one saved session: correct vs attempted, form accuracy, the most
// common mistake and one line per set. LiveWorkoutScreen will open it after
// saving a workout (once Member A's Day 9 pull request is merged), and the
// History screen will open it for a past session.

import 'package:flutter/material.dart';

import '../models/exercise_info.dart';
import '../models/workout_records.dart';
import '../services/database_service.dart';

class SessionSummaryScreen extends StatefulWidget {
  const SessionSummaryScreen({
    super.key,
    required this.database,
    required this.sessionId,
  });

  final DatabaseService database;
  final int sessionId;

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  late final Future<SessionSummary?> _summary = widget.database.getSummary(
    widget.sessionId,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout summary')),
      body: FutureBuilder<SessionSummary?>(
        future: _summary,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = snapshot.data;
          if (snapshot.hasError || s == null) {
            return const Center(
              child: Text('This session could not be loaded.'),
            );
          }
          return SessionSummaryView(
            summary: s,
            onDone: () => Navigator.pop(context),
          );
        },
      ),
    );
  }
}

/// The summary itself, without the loading. Separate so tests can show it
/// directly.
class SessionSummaryView extends StatelessWidget {
  const SessionSummaryView({super.key, required this.summary, this.onDone});

  final SessionSummary summary;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final s = summary;
    final accuracy = s.formAccuracy;
    final mistake = s.topMistake;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          s.attemptedReps == 0
              ? 'No reps in this session'
              : '${s.correctReps} correct of ${s.attemptedReps} attempted',
          style: textTheme.headlineSmall,
        ),
        if (accuracy != null) ...[
          const SizedBox(height: 4),
          Text('Form accuracy: ${(accuracy * 100).round()}%'),
        ],
        if (mistake != null) ...[
          const SizedBox(height: 4),
          Text(
            'Most common mistake: ${_checkLabel(mistake)} '
            '(${_reps(s.topMistakeCount)})',
          ),
        ],
        const SizedBox(height: 24),
        Text('Sets', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final set in s.sets)
          Card(
            child: ListTile(
              title: Text(
                '${_exerciseName(set.exerciseId)}, set ${set.setNumber}',
              ),
              subtitle: Text(_setLine(set)),
            ),
          ),
        if (onDone != null) ...[
          const SizedBox(height: 24),
          FilledButton(onPressed: onDone, child: const Text('Done')),
        ],
      ],
    );
  }
}

/// 'bodyweight_squat' -> 'Bodyweight squat'.
String _exerciseName(String id) {
  for (final e in fakeExercises) {
    if (e.id == id) return e.name;
  }
  return id;
}

/// 'torso_lean' -> 'Torso lean'.
String _checkLabel(String name) {
  final words = name.replaceAll('_', ' ');
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

String _reps(int n) => n == 1 ? '1 rep' : '$n reps';

String _setLine(SetSummary set) {
  final held = set.holdSeconds;
  if (held != null) {
    final target = set.targetSeconds;
    return target == null
        ? '${held.floor()} seconds held'
        : '${held.floor()} of $target seconds held';
  }
  final line = '${set.correctReps} correct of ${set.attemptedReps} attempted';
  return set.targetReps == null ? line : '$line (target ${set.targetReps})';
}
