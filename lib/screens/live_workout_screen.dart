import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/exercise_info.dart';
import '../models/workout_records.dart';
import '../models/workout_view.dart';
import '../services/workout_source.dart';
import '../widgets/rest_view.dart';

// Live workout screen (roadmap Part 10) for every set of one exercise:
// counters, cue banner, rep result color, Pause and Stop, then rest between
// sets (RestView) and a summary at the end. Reads only WorkoutView, so the
// fake source and the engine both fit.
class LiveWorkoutScreen extends StatefulWidget {
  const LiveWorkoutScreen({
    super.key,
    required this.exercise,
    required this.source,
    required this.plan,
  });

  final ExerciseInfo exercise;
  final WorkoutSource source;

  /// Target per set, number of sets and rest (Member C's RoutineItem, so a
  /// routine is just a list of these).
  final RoutineItem plan;

  @override
  State<LiveWorkoutScreen> createState() => _LiveWorkoutScreenState();
}

class _LiveWorkoutScreenState extends State<LiveWorkoutScreen> {
  StreamSubscription<WorkoutView>? _sub;
  int _setNumber = 1;
  bool _resting = false;
  bool _finished = false;
  final _results = <String>[];

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
    final reached = _isHold ? v.holdSeconds >= _target : v.correct >= _target;
    if (!reached) return;
    widget.source.pause();
    _results.add(_summary(v));
    setState(() {
      if (_setNumber < widget.plan.sets) {
        _resting = true;
      } else {
        _finished = true;
      }
    });
  }

  String _summary(WorkoutView v) => _isHold
      ? '${v.holdSeconds.floor()} seconds held'
      : '${v.correct} correct of ${v.attempted} attempted';

  void _startNextSet() {
    setState(() {
      _resting = false;
      _setNumber++;
    });
    widget.source.resume();
    widget.source.beginSet();
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.source.stop();
    WakelockPlus.disable();
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
                  ],
                ),
              ),
              if (v.paused && !_resting && !_finished)
                _PausedOverlay(personVisible: v.personVisible),
              if (_resting)
                RestView(
                  key: ValueKey(_setNumber),
                  seconds: widget.plan.restSec,
                  lastSet: _results.last,
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
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (_finished)
                _FinishedOverlay(
                  results: _results,
                  onDone: () => Navigator.pop(context),
                ),
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
