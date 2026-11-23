import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/exercise_info.dart';
import '../models/strictness.dart';
import '../models/workout_records.dart';
import '../models/workout_view.dart';
import '../services/database_service.dart';
import '../services/fatigue.dart';
import '../services/overload.dart';
import '../services/workout_launcher.dart';
import '../services/workout_source.dart';
import '../widgets/rest_view.dart';
import 'session_summary_screen.dart';

// Live workout screen (roadmap Part 10) for every set of one exercise:
// counters, cue banner, rep result color, Pause and Stop, then rest between
// sets (RestView) and a summary at the end. Reads only WorkoutView, so the
// fake source and the engine both fit.
// Saving (Member C): each set's reps come from source.takeSetReps(); Stop or
// Done saves the session (a stopped set too) and opens SessionSummaryScreen.
// Fatigue warnings (Member C, fatigue.dart): a red banner after 3 failed reps
// in a row, and a note on the rest screen when a set falls behind set 1.
// Exercise check (Member C, exercise_check.dart): the source's
// exerciseWarning (wrong posture or no movement) in the same red banner.
// Overload (Member C, overload.dart): target + 5 attempts without reaching
// the target replaces the failed-in-a-row warning in that banner.
// Routine runner: with a RoutineRun, the last set of an exercise is followed
// by a rest and the next exercise's setup check; the whole routine saves as
// one session. Layout (design H): camera with the cue on it, and a panel with
// the sets, the count, Pause and Stop (beside the camera in landscape, below
// it in portrait).
class LiveWorkoutScreen extends StatefulWidget {
  const LiveWorkoutScreen({
    super.key,
    required this.exercise,
    required this.source,
    required this.plan,
    required this.strictness,
    this.run,
  });

  final ExerciseInfo exercise;
  final WorkoutSource source;

  /// Target per set, number of sets and rest (Member C's RoutineItem, so a
  /// routine is just a list of these).
  final RoutineItem plan;

  /// Saved with the session (Member C).
  final Strictness strictness;

  /// Set when this exercise is part of a routine (Custom Workout Mode).
  final RoutineRun? run;

  @override
  State<LiveWorkoutScreen> createState() => _LiveWorkoutScreenState();
}

class _LiveWorkoutScreenState extends State<LiveWorkoutScreen> {
  StreamSubscription<WorkoutView>? _sub;
  int _setNumber = 1;
  bool _resting = false;
  bool _betweenExercises = false; // routine: rest before the next exercise
  bool _handedOver = false; // routine: the next exercise took over
  bool _finished = false;
  final _results = <String>[];
  final _startedAt = DateTime.now();
  final _sets = <SetRecord>[];
  Future<int?>? _saving;
  bool _leaving = false;
  int _seenAttempted = 0; // reps of this set already looked at
  int _failedStreak = 0;
  String? _warning; // shown during the set
  String? _restNote; // shown on the rest screen

  bool get _isHold => widget.exercise.type == ExerciseType.hold;

  int get _target =>
      (_isHold ? widget.plan.targetSeconds : widget.plan.targetReps) ?? 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _sub = widget.source.updates.listen(_onUpdate);
  }

  void _onUpdate(WorkoutView v) {
    // While resting or paused, the counts still belong to the set that ended.
    if (_resting || _betweenExercises || _finished || v.paused) return;
    if (v.attempted > _seenAttempted) {
      _seenAttempted = v.attempted;
      _failedStreak = v.lastRepCorrect == false ? _failedStreak + 1 : 0;
      final warning =
          warnTooManyReps(
            attempted: v.attempted,
            correct: v.correct,
            target: _target,
          ) ??
          warnDuringSet(_failedStreak);
      if (warning != _warning) setState(() => _warning = warning);
    }
    final reached = _isHold ? v.holdSeconds >= _target : v.correct >= _target;
    if (!reached) return;
    widget.source.pause();
    _results.add(_summary(v));
    _sets.add(_setRecord(v));
    _restNote = warnAfterSet(_sets);
    setState(() {
      if (_setNumber < widget.plan.sets) {
        _resting = true;
      } else if (widget.run != null && !widget.run!.isLast) {
        _betweenExercises = true;
      } else {
        _finished = true;
        _saving = _save();
      }
    });
  }

  /// The set that just ended (or was stopped), with its reps from the source.
  SetRecord _setRecord(WorkoutView v) => SetRecord(
    exerciseId: widget.plan.exerciseId,
    setNumber: _setNumber,
    targetReps: widget.plan.targetReps,
    targetSeconds: widget.plan.targetSeconds,
    holdSeconds: _isHold ? v.holdSeconds : null,
    reps: widget.source.takeSetReps(),
  );

  /// Saves the session once. Null when nothing was done or saving failed.
  /// A routine saves every exercise's sets in one session.
  Future<int?> _save() async {
    final run = widget.run;
    if (run != null) return run.save(_sets);
    final done = _sets.any(
      (s) => s.reps.isNotEmpty || (s.holdSeconds ?? 0) >= 1,
    );
    if (!done) return null;
    try {
      return await DatabaseService.instance.saveSession(
        SessionRecord(
          startedAt: _startedAt,
          endedAt: DateTime.now(),
          mode: 'single',
          strictness: widget.strictness.name,
          sets: _sets,
        ),
      );
    } catch (e) {
      debugPrint('Saving the session failed: $e');
      return null;
    }
  }

  /// Stop or Done: save what was done, then show the summary, or just go back
  /// when there is nothing to show.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    if (_saving == null) {
      if (!_resting && !_betweenExercises) {
        final stopped = _setRecord(widget.source.current);
        if (stopped.reps.isNotEmpty || (stopped.holdSeconds ?? 0) >= 1) {
          _sets.add(stopped);
        }
      }
      _saving = _save();
    }
    final id = await _saving;
    if (!mounted) return;
    if (id == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SessionSummaryScreen(
          database: DatabaseService.instance,
          sessionId: id,
        ),
      ),
    );
  }

  String _summary(WorkoutView v) => _isHold
      ? '${v.holdSeconds.floor()} seconds held'
      : '${v.correct} correct of ${v.attempted} attempted';

  void _startNextSet() {
    setState(() {
      _resting = false;
      _setNumber++;
      _seenAttempted = 0;
      _failedStreak = 0;
      _warning = null;
    });
    widget.source.resume();
    widget.source.beginSet();
  }

  /// Routine: this exercise is done, so hand over to the next one's setup.
  void _nextExercise() {
    final run = widget.run!;
    run.sets.addAll(_sets);
    run.index++;
    _handedOver = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => run.setupScreen()),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.source.stop();
    WakelockPlus.disable();
    // The next exercise's setup check has already set its own orientation.
    if (!_handedOver) SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      body: StreamBuilder<WorkoutView>(
        stream: widget.source.updates,
        initialData: widget.source.current,
        builder: (context, snapshot) {
          final v = snapshot.data!;
          final camera = _camera(v);
          final panel = SafeArea(
            left: !landscape,
            top: landscape,
            child: landscape
                ? SingleChildScrollView(child: _panel(context, v))
                : _panel(context, v),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              landscape
                  ? Row(
                      children: [
                        Expanded(child: camera),
                        SizedBox(width: 300, child: panel),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: camera),
                        panel,
                      ],
                    ),
              if (_resting)
                RestView(
                  key: ValueKey(_setNumber),
                  seconds: widget.plan.restSec,
                  lastSet: _restNote == null
                      ? _results.last
                      : '${_results.last}\n\n$_restNote',
                  next: 'Set ${_setNumber + 1} of ${widget.plan.sets}',
                  onDone: _startNextSet,
                ),
              if (_betweenExercises)
                RestView(
                  key: const ValueKey('next exercise'),
                  seconds: widget.plan.restSec,
                  lastSet: _results.last,
                  next: 'Next exercise: ${widget.run!.nextName}',
                  onDone: _nextExercise,
                ),
              if (_finished)
                _FinishedOverlay(results: _results, onDone: _leave),
            ],
          );
        },
      ),
    );
  }

  /// The camera with the rep color frame, the cue and warnings on top.
  Widget _camera(WorkoutView v) {
    final repColor = v.lastRepCorrect == null
        ? null
        : (v.lastRepCorrect! ? Colors.greenAccent : Colors.redAccent);
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: widget.source.buildPreview()),
          // Placeholder for red and green joints: a frame in the latest
          // rep's color.
          if (repColor != null)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: repColor, width: 6),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (v.cue != null) _CueBanner(cue: v.cue!),
                  if (_warning != null) ...[
                    const SizedBox(height: 8),
                    _WarningBanner(text: _warning!),
                  ],
                  if (v.exerciseWarning != null) ...[
                    const SizedBox(height: 8),
                    _WarningBanner(text: v.exerciseWarning!),
                  ],
                ],
              ),
            ),
          ),
          if (v.paused && !_resting && !_betweenExercises && !_finished)
            _PausedOverlay(personVisible: v.personVisible),
        ],
      ),
    );
  }

  /// Exercise name, the sets (last, now, next), the count, Pause and Stop.
  Widget _panel(BuildContext context, WorkoutView v) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final run = widget.run;
    final where = run == null
        ? 'Single exercise'
        : '${run.routine.name}, exercise ${run.index + 1} of '
              '${run.routine.items.length}';
    final now = _isHold
        ? '${v.holdSeconds.floor()} of $_target s'
        : '${v.correct} of $_target';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.exercise.name,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            where,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_setNumber > 1)
            _SetRow(
              label: 'Set ${_setNumber - 1}',
              value: _results[_setNumber - 2],
            ),
          _SetRow(label: 'Set $_setNumber, now', value: now, current: true),
          if (_setNumber < widget.plan.sets)
            _SetRow(
              label: 'Set ${_setNumber + 1}',
              value: 'next, after ${widget.plan.restSec} s rest',
            ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _isHold ? '${v.holdSeconds.floor()}' : '${v.correct}',
                style: text.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isHold
                      ? 'seconds held of $_target'
                      : 'correct, ${v.attempted} attempted',
                  style: text.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: Icon(v.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(v.paused ? 'Resume' : 'Pause'),
                  onPressed: _resting || _betweenExercises
                      ? null
                      : (v.paused ? widget.source.resume : widget.source.pause),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                  ),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  onPressed: _leave,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One line of the set list; the set in progress is highlighted.
class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.label,
    required this.value,
    this.current = false,
  });

  final String label;
  final String value;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: current ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
      fontWeight: current ? FontWeight.w700 : null,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: current ? scheme.secondaryContainer : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(label, style: style),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _CueBanner extends StatelessWidget {
  const _CueBanner({required this.cue});

  final String cue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.record_voice_over),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              cue,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fatigue warning during a set: red, so it stands apart from form cues.
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _PausedOverlay extends StatelessWidget {
  const _PausedOverlay({required this.personVisible});

  final bool personVisible;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              personVisible ? Icons.pause_circle : Icons.person_search,
              size: 72,
              color: Colors.white,
            ),
            const SizedBox(height: 12),
            Text(
              personVisible ? 'Paused' : 'Step back into view to continue',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishedOverlay extends StatelessWidget {
  const _FinishedOverlay({required this.results, required this.onDone});

  final List<String> results;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 72, color: Colors.greenAccent),
            const SizedBox(height: 12),
            const Text(
              'Workout complete',
              style: TextStyle(color: Colors.white, fontSize: 28),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < results.length; i++)
              Text(
                'Set ${i + 1}: ${results[i]}',
                style: const TextStyle(color: Colors.white70),
              ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
