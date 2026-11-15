import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/exercise_info.dart';
import '../models/workout_view.dart';
import 'workout_source.dart';

// Pretend workout for building the screens on the emulator.
// Shows the real webcam but makes up everything else:
//   1 s: person found. 2 s: ready, so the countdown can start.
//   After the set begins: one rep every 3 s, every third rep fails with a cue
//   (hold exercises count seconds instead), and the person "leaves" for 3 s
//   after rep 5 (or 10 s of holding) so the automatic pause can be seen.
class FakeWorkoutSource implements WorkoutSource {
  FakeWorkoutSource(this.exercise);

  final ExerciseInfo exercise;
  final _updates = StreamController<WorkoutView>.broadcast();
  WorkoutView _current = const WorkoutView();
  CameraController? _camera;
  Timer? _timer;
  bool _stopped = false;

  int _tick = 0; // 100 ms steps since start()
  int _awayUntil = -1;
  bool _counting = false;
  bool _manualPause = false;
  int _correct = 0;
  int _attempted = 0;
  String? _cue;
  bool? _lastRepCorrect;
  double _hold = 0;

  bool get _isHold => exercise.type == ExerciseType.hold;

  @override
  Stream<WorkoutView> get updates => _updates.stream;

  @override
  WorkoutView get current => _current;

  @override
  Future<void> start() async {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _step());
    if (!(await Permission.camera.request()).isGranted) return;
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (_stopped) {
        await controller.dispose();
        return;
      }
      _camera = controller;
    } catch (e) {
      debugPrint('FakeWorkoutSource: no camera ($e)');
    }
  }

  void _step() {
    _tick++;
    final away = _tick < _awayUntil;
    if (_counting && !_manualPause && !away) {
      if (_isHold) {
        _hold += 0.1;
        if (_hold >= 10 && _awayUntil < 0) _awayUntil = _tick + 30;
      } else if (_tick % 30 == 0) {
        _attempted++;
        final ok = _attempted % 3 != 0;
        if (ok) _correct++;
        _lastRepCorrect = ok;
        _cue = ok ? null : 'Go lower.';
        if (_attempted == 5) _awayUntil = _tick + 30;
      }
    }
    _current = WorkoutView(
      personVisible: _tick >= 10 && !away,
      ready: _tick >= 20 && !away,
      paused: _manualPause || (_counting && away),
      correct: _correct,
      attempted: _attempted,
      cue: _cue,
      holdSeconds: _hold,
      lastRepCorrect: _lastRepCorrect,
    );
    _updates.add(_current);
  }

  @override
  Widget buildPreview() {
    final c = _camera;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black, child: SizedBox.expand());
    }
    return CameraPreview(c);
  }

  @override
  void beginSet() {
    _correct = 0;
    _attempted = 0;
    _hold = 0;
    _cue = null;
    _lastRepCorrect = null;
    _awayUntil = -1;
    _manualPause = false;
    _counting = true;
  }

  @override
  void pause() => _manualPause = true;

  @override
  void resume() => _manualPause = false;

  @override
  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    await _camera?.dispose();
    _camera = null;
    await _updates.close();
  }
}
