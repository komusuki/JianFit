import 'dart:async';

import 'package:flutter/material.dart';

import '../models/exercise_info.dart';
import '../models/workout_view.dart';
import '../services/workout_source.dart';

// Camera setup check (roadmap Part 10): placement instructions, a body
// outline, and a 3-2-1 countdown once the source says the person is ready.
class SetupCheckScreen extends StatefulWidget {
  const SetupCheckScreen({
    super.key,
    required this.exercise,
    required this.source,
  });

  final ExerciseInfo exercise;
  final WorkoutSource source;

  @override
  State<SetupCheckScreen> createState() => _SetupCheckScreenState();
}

class _SetupCheckScreenState extends State<SetupCheckScreen> {
  StreamSubscription<WorkoutView>? _sub;
  Timer? _countdownTimer;
  int? _countdown;

  @override
  void initState() {
    super.initState();
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
    // Step 8 replaces this with opening the live workout screen.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Live workout screen is not built yet')),
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
    widget.source.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: Colors.white);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text('Set up: ${widget.exercise.name}')),
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
    );
  }
}
