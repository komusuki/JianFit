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
class LiveWorkoutScreen extends StatefulWidget {
  const LiveWorkoutScreen({
    super.key,
    required this.exercise,
    required this.source,
    required this.plan,
    required this.strictness,
  });

  final ExerciseInfo exercise;
  final WorkoutSource source;

  /// Target per set, number of sets and rest (Member C's RoutineItem, so a
  /// routine is just a list of these).
  final RoutineItem plan;

  /// Saved with the session (Member C).
  final Strictness strictness;

  @override
  State<LiveWorkoutScreen> createState() => _LiveWorkoutScreenState();
}

class _LiveWorkoutScreenState extends State<LiveWorkoutScreen> {
  StreamSubscription<WorkoutView>? _sub;
  int _setNumber = 1;
  bool _resting = false;
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
    if (_resting || _finished || v.paused) return;
    if (v.attempted > _seenAttempted) {
      _seenAttempted = v.attempted;
      _failedStreak = v.lastRepCorrect == false ? _failedStreak + 1 : 0;
      final warning = warnDuringSet(_failedStreak);
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
  Future<int?> _save() async {
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
      if (!_resting) {
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

  @override
  void dispose() {
    _sub?.cancel();
    widget.source.stop();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          '${widget.exercise.name}, set $_setNumber of ${widget.plan.sets}',
        ),
      ),
      body: StreamBuilder<WorkoutView>(
        stream: widget.source.updates,
        initialData: widget.source.current,
        builder: (context, snapshot) {
          final v = snapshot.data!;
          final repColor = v.lastRepCorrect == null
              ? null
              : (v.lastRepCorrect! ? Colors.greenAccent : Colors.redAccent);
          return Stack(
            fit: StackFit.expand,
            children: [
              Center(child: widget.source.buildPreview()),
              // Placeholder for red and green joints: a frame in the
              // latest rep's color.
              if (repColor != null)
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: repColor, width: 6),
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Counters(view: v, isHold: _isHold, target: _target),
                    if (v.cue != null) ...[
                      const SizedBox(height: 8),
                      _CueBanner(cue: v.cue!),
                    ],
                    if (_warning != null) ...[
                      const SizedBox(height: 8),
                      _WarningBanner(text: _warning!),
                    ],
                  ],
                ),
              ),
              if (v.paused && !_resting && !_finished)
                _PausedOverlay(personVisible: v.personVisible),
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
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        icon: Icon(v.paused ? Icons.play_arrow : Icons.pause),
                        label: Text(v.paused ? 'Resume' : 'Pause'),
                        onPressed: _resting
                            ? null
                            : (v.paused
                                  ? widget.source.resume
                                  : widget.source.pause),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                        onPressed: _leave,
                      ),
                    ),
                  ],
                ),
              ),
              if (_finished)
                _FinishedOverlay(results: _results, onDone: _leave),
            ],
          );
        },
      ),
    );
  }
}

class _Counters extends StatelessWidget {
  const _Counters({
    required this.view,
    required this.isHold,
    required this.target,
  });

  final WorkoutView view;
  final bool isHold;
  final int target;

  @override
  Widget build(BuildContext context) {
    const big = TextStyle(
      color: Colors.white,
      fontSize: 36,
      fontWeight: FontWeight.bold,
    );
    const small = TextStyle(color: Colors.white70);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: isHold
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${view.holdSeconds.floor()} / $target s', style: big),
                const Text('Hold time', style: small),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${view.correct} / $target', style: big),
                    const Text('Correct', style: small),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${view.attempted}', style: big),
                    const Text('Attempted', style: small),
                  ],
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
