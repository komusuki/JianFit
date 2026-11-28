import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/exercise_info.dart';
import '../models/strictness.dart';
import '../models/workout_records.dart';
import '../models/workout_view.dart';
import '../services/database_service.dart';
import '../services/workout_launcher.dart';
import '../services/workout_source.dart';
import 'live_workout_screen.dart';
import 'session_summary_screen.dart';

// Camera setup check (roadmap Part 10): placement instructions, a body
// outline, and a 3-2-1 countdown once the source says the person is ready.
class SetupCheckScreen extends StatefulWidget {
  const SetupCheckScreen({
    super.key,
    required this.exercise,
    required this.source,
    required this.plan,
    required this.strictness,
    required this.landscape,
    this.run,
  });

  final ExerciseInfo exercise;
  final WorkoutSource source;

  /// Target, sets and rest for this exercise.
  final RoutineItem plan;

  /// Passed on to the live workout screen (saved with the session).
  final Strictness strictness;

  /// Lock the screen to landscape (floor exercises) or portrait.
  final bool landscape;

  /// Set when this exercise is part of a routine (Custom Workout Mode).
  final RoutineRun? run;

  @override
  State<SetupCheckScreen> createState() => _SetupCheckScreenState();
}

class _SetupCheckScreenState extends State<SetupCheckScreen> {
  StreamSubscription<WorkoutView>? _sub;
  Timer? _countdownTimer;
  int? _countdown;
  bool _handedOver = false;
  bool _stopping = false;
  bool _skipped = false; // routine: moved on to the next exercise's setup

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
      widget.landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
    _sub = widget.source.updates.listen(_onUpdate);
    widget.source.start();
  }

  void _onUpdate(WorkoutView v) {
    if (v.ready && _countdownTimer == null) {
      _startCountdown();
    } else if (!v.ready && _countdownTimer != null) {
      _countdownTimer!.cancel();
      _countdownTimer = null;
      setState(() => _countdown = null);
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 3);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown == 1) {
        t.cancel();
        _onCountdownDone();
      } else {
        setState(() => _countdown = _countdown! - 1);
      }
    });
  }

  void _onCountdownDone() {
    widget.source.beginSet();
    _handedOver = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LiveWorkoutScreen(
          exercise: widget.exercise,
          source: widget.source,
          plan: widget.plan,
          strictness: widget.strictness,
          run: widget.run,
        ),
      ),
    );
  }

  /// Back during a routine, after at least one exercise: save the exercises
  /// already done and show their summary, so they are not lost.
  Future<void> _stopRoutine() async {
    if (_stopping) return;
    _stopping = true;
    final id = await widget.run!.save(const []);
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

  /// Routine: skip this exercise (pilot request, Day 20). Goes to the next
  /// exercise's setup, or ends the routine like Back on the last one.
  void _skip() {
    if (_handedOver || _skipped || _stopping) return;
    final run = widget.run!;
    _countdownTimer?.cancel();
    if (run.isLast) {
      _stopRoutine();
      return;
    }
    _skipped = true;
    run.index++;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => run.setupScreen()),
    );
  }

  String _status(WorkoutView v) {
    if (_countdown != null) return 'Hold still...';
    if (v.ready) return 'Good. Get ready.';
    if (v.personVisible) return 'Almost there. Stay in view.';
    return 'Step back until your whole body is inside the outline.';
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _sub?.cancel();
    if (!_handedOver) {
      widget.source.stop();
      // After a skip, the next setup check has already set its orientation.
      if (!_skipped) SystemChrome.setPreferredOrientations([]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: Colors.white);
    final routineDone = widget.run?.sets.isNotEmpty ?? false;
    return PopScope(
      canPop: !routineDone,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopRoutine();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text('Set up: ${widget.exercise.name}'),
          actions: [
            if (widget.run != null)
              TextButton(onPressed: _skip, child: const Text('Skip')),
          ],
        ),
        body: StreamBuilder<WorkoutView>(
          stream: widget.source.updates,
          initialData: widget.source.current,
          builder: (context, snapshot) {
            final v = snapshot.data!;
            return Stack(
              fit: StackFit.expand,
              children: [
                Center(child: widget.source.buildPreview()),
                Center(
                  child: Icon(
                    Icons.accessibility_new,
                    size: 280,
                    color: (v.ready ? Colors.greenAccent : Colors.white)
                        .withValues(alpha: 0.5),
                  ),
                ),
                if (_countdown != null)
                  Center(
                    child: Text(
                      '$_countdown',
                      style: const TextStyle(
                        fontSize: 120,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 32,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.exercise.cameraView} view. '
                          '${widget.exercise.placement}',
                          style: white,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _status(v),
                          style: white.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
