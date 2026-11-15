import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/exercise_info.dart';
import '../models/workout_view.dart';
import '../services/workout_source.dart';

// Live workout screen (roadmap Part 10): camera preview, rep result color,
// correct and attempted counters, cue banner, hold timer, Pause and Stop.
// Reads only WorkoutView, so the fake source and the engine both fit.
class LiveWorkoutScreen extends StatefulWidget {
  const LiveWorkoutScreen({
    super.key,
    required this.exercise,
    required this.source,
    required this.target,
  });

  final ExerciseInfo exercise;
  final WorkoutSource source;

  /// Correct reps, or seconds for hold exercises.
  final int target;

  @override
  State<LiveWorkoutScreen> createState() => _LiveWorkoutScreenState();
}

class _LiveWorkoutScreenState extends State<LiveWorkoutScreen> {
  StreamSubscription<WorkoutView>? _sub;
  bool _setDone = false;

  bool get _isHold => widget.exercise.type == ExerciseType.hold;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _sub = widget.source.updates.listen((v) {
      final reached = _isHold
          ? v.holdSeconds >= widget.target
          : v.correct >= widget.target;
      if (reached && !_setDone) {
        widget.source.pause();
        setState(() => _setDone = true);
      }
    });
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
      appBar: AppBar(title: Text(widget.exercise.name)),
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
                    _Counters(view: v, isHold: _isHold, target: widget.target),
                    if (v.cue != null) ...[
                      const SizedBox(height: 8),
                      _CueBanner(cue: v.cue!),
                    ],
                  ],
                ),
              ),
              if (v.paused && !_setDone)
                _PausedOverlay(personVisible: v.personVisible),
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
                        onPressed: v.paused
                            ? widget.source.resume
                            : widget.source.pause,
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
              if (_setDone)
                _SetDoneOverlay(
                  summary: _isHold
                      ? '${v.holdSeconds.floor()} seconds held'
                      : '${v.correct} correct of ${v.attempted} attempted',
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

class _SetDoneOverlay extends StatelessWidget {
  const _SetDoneOverlay({required this.summary, required this.onDone});

  final String summary;
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
              'Set complete',
              style: TextStyle(color: Colors.white, fontSize: 28),
            ),
            const SizedBox(height: 4),
            Text(summary, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            FilledButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}