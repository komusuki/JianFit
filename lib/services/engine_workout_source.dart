import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../engine/cue_manager.dart';
import '../engine/exercise_check.dart';
import '../engine/form_judge.dart';
import '../engine/hold_timer.dart';
import '../engine/landmarks.dart';
import '../engine/measurement_layer.dart';
import '../engine/rep_counter.dart';
import '../models/exercise_definition.dart';
import '../models/exercise_info.dart';
import '../models/strictness.dart';
import '../models/workout_records.dart';
import '../models/workout_view.dart';
import '../widgets/skeleton_painter.dart';
import 'cue_speaker.dart';
import 'pose_service.dart';
import 'rep_records.dart';
import 'settings_service.dart';
import 'workout_source.dart';

// The real workout source (Day 8). Owner: Member A.
// Front camera and ML Kit, then the engine in the same order as
// CameraTestScreen: measurement layer, rep counter (reset on an automatic
// pause), form judge, cue manager. Drives Member B's setup check and live
// workout screens through the WorkoutSource contract.
// Before beginSet() only the measurement layer runs (setup and ready).
// Holds (Day 9) use HoldTimer instead of the rep counter; lunges report
// correct reps per front leg; the jump squat's jump detection is inside the
// rep counter.
class EngineWorkoutSource implements WorkoutSource {
  EngineWorkoutSource(this.exercise, this.strictness)
    : _layer = MeasurementLayer(exercise.config),
      _counter = exercise.info.type == ExerciseType.hold
          ? null
          : RepCounter.forExercise(exercise.config),
      _hold = exercise.info.type == ExerciseType.hold
          ? HoldTimer(exercise.formChecks, strictness)
          : null;

  final ExerciseDefinition exercise;
  final Strictness strictness;

  final MeasurementLayer _layer;
  final RepCounter? _counter; // rep exercises
  final HoldTimer? _hold; // hold exercises
  final _cues = CueManager();
  late final _check = ExerciseCheck(exercise.config); // Member C
  String? _checkMessage;
  final _speaker = CueSpeaker();
  final _poseService = PoseService();
  final _clock = Stopwatch(); // t_ms for the engine
  final _fpsWatch = Stopwatch();
  final _updates = StreamController<WorkoutView>.broadcast();
  WorkoutView _current = const WorkoutView();

  // One engine camera at a time. In a routine, the next exercise's setup
  // screen starts its source before the previous live screen is disposed,
  // and the front camera cannot be opened twice (black preview). So each
  // source waits until the previous one has released the camera (at most 3 s).
  static Future<void> _cameraFree = Future.value();
  final _released = Completer<void>();

  CameraController? _controller;
  CameraDescription? _camera;
  CameraImage? _pending;
  int _pendingMs = 0;
  bool _processing = false;
  bool _stopped = false;
  int _frames = 0; // processed frames since the last FPS line
  int _cameraFrames = 0; // frames the camera delivered since the last FPS line

  // The latest processed frame, for the skeleton. Drawn smoothed (see
  // _smoothForDrawing) so the dots don't shake; display only.
  Pose? _pose;
  InputImageRotation? _rotation;
  Size? _imageSize;
  bool _personVisible = false;

  bool _counting = false;
  bool _manualPause = false;
  bool _autoPaused = false;
  int _correct = 0;
  int _attempted = 0;
  int _correctLeft = 0;
  int _correctRight = 0;
  String? _cue;
  bool? _lastRepCorrect;
  final _setReps = <RepRecord>[]; // this set's reps, for saving (Member C)

  @override
  Stream<WorkoutView> get updates => _updates.stream;

  @override
  WorkoutView get current => _current;

  @override
  Future<void> start() async {
    final previous = _cameraFree;
    _cameraFree = _released.future;
    await previous.timeout(
      const Duration(seconds: 3),
      onTimeout: () => debugPrint('ENGINE: previous camera not released'),
    );
    if (_stopped) return;
    _cues.voiceOn = await SettingsService.loadVoiceOn(); // Member B's setting
    await _speaker.init();
    if (!(await Permission.camera.request()).isGranted) {
      debugPrint('ENGINE: camera permission denied');
      return;
    }
    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await controller.initialize();
    if (_stopped) {
      await controller.dispose();
      return;
    }
    _camera = camera;
    _controller = controller;
    _clock.start();
    _fpsWatch.start();
    await controller.startImageStream(_onFrame);
    debugPrint(
      'ENGINE started: ${exercise.id}, strictness ${strictness.name}, '
      'voice ${_cues.voiceOn ? 'on' : 'off'}',
    );
    _publish(); // the camera is ready: show the preview
  }

  void _onFrame(CameraImage image) {
    _cameraFrames++;
    final tMs = _clock.elapsedMilliseconds; // time the frame arrived
    if (_processing) {
      _pending = image; // keep only the newest frame
      _pendingMs = tMs;
      return;
    }
    _processLoop(image, tMs);
  }

  Future<void> _processLoop(CameraImage first, int firstMs) async {
    _processing = true;
    CameraImage? image = first;
    var tMs = firstMs;
    while (image != null && !_stopped) {
      _pending = null;
      try {
        await _handle(image, tMs);
      } catch (e) {
        if (!_stopped) debugPrint('ENGINE frame error: $e');
      }
      image = _pending;
      tMs = _pendingMs;
    }
    _processing = false;
  }

  Future<void> _handle(CameraImage image, int tMs) async {
    final controller = _controller;
    final camera = _camera;
    if (controller == null || camera == null) return;
    final orientation = controller.value.deviceOrientation;
    final poses = await _poseService.process(image, camera, orientation);
    if (poses == null || _stopped) return;
    final pose = poses.isEmpty ? null : poses.first;
    final points = PoseService.toPoints(pose);

    final wasReady = _layer.isReady;
    final frame = _layer.process(points, tMs);
    if (!wasReady && _layer.isReady) {
      debugPrint(
        'ENGINE setup done: side=${_layer.side!.name} '
        'baseline=${_layer.baseline}',
      );
    }
    if (frame.status == FrameStatus.paused) {
      // No usable frame for 2 s: setup starts again (ready goes false).
      _autoPaused = true;
      _counter?.reset(keepCount: true);
      debugPrint('ENGINE paused: no judgeable frame for 2 s');
    } else if (frame.status == FrameStatus.judged) {
      _autoPaused = false;
      if (_counting && !_manualPause) {
        final repsBefore = _attempted;
        if (_hold != null) {
          _holdFrame(frame, tMs);
        } else {
          _count(frame, tMs);
        }
        _checkMessage = _check.update(
          lean: torsoLean(points, _layer.side),
          main: _hold == null
              ? frame.values[exercise.config.mainMeasurement]
              : null,
          tMs: tMs,
          repDone: _attempted != repsBefore,
        );
      }
    }
    // Not judged (joints hidden, paused, or setting up again): posture only,
    // so lying down still shows its message (Member C, fix/lying-down-banner).
    if (frame.status != FrameStatus.judged && _counting && !_manualPause) {
      _checkMessage = _check.update(
        lean: torsoLean(points, _layer.side),
        tMs: tMs,
      );
    }

    _rotation = _poseService.rotationFor(camera, orientation);
    _imageSize = Size(image.width.toDouble(), image.height.toDouble());
    _personVisible = _layer.hasPerson(points);
    _pose = pose != null && _personVisible ? _smoothForDrawing(pose) : null;
    _logFps();
    _publish();
  }

  void _count(FrameResult frame, int tMs) {
    final main = frame.values[exercise.config.mainMeasurement];
    if (main == null) return;
    final rep = _counter!.update(main, frame.values, tMs, leg: frame.frontLeg);
    if (rep == null) return;
    final verdict = judgeRep(rep, exercise.formChecks, strictness);
    _attempted++;
    _setReps.add(repRecordFrom(_attempted, rep, verdict));
    if (verdict.correct) {
      _correct++;
      if (rep.leg == Side.left) _correctLeft++;
      if (rep.leg == Side.right) _correctRight++;
    }
    _lastRepCorrect = verdict.correct;
    final cue = _cues.onRep(verdict, tMs);
    _cue = cue.text;
    if (cue.speak) _say(cue.text!, tMs);
    final names = verdict.failed.map((c) => c.name).join(', ');
    final result = verdict.correct ? 'correct' : 'attempted ($names)';
    final said = cue.text == null
        ? ''
        : '  cue "${cue.text}" ${cue.speak ? 'spoken' : 'shown only'}';
    final leg = rep.leg == null ? '' : ' (${rep.leg!.name} leg)';
    debugPrint('ENGINE rep $_attempted$leg: $result$said');
    for (final r in verdict.results) {
      debugPrint(
        '  ${r.check.name}: value=${r.value?.toStringAsFixed(3) ?? '-'} '
        '${r.check.kind.name} ${r.limit} -> '
        '${r.passed == null ? 'skipped' : (r.passed! ? 'pass' : 'FAIL')}',
      );
    }
    for (final c in cue.tips) {
      debugPrint('ENGINE tip card: ${c.name} 3 times this set');
    }
  }

  void _holdFrame(FrameResult frame, int tMs) {
    final hold = _hold!;
    final before = hold.state;
    final broke = hold.update(frame.values, tMs);
    if (broke != null) {
      final cue = _cues.onRep(broke, tMs);
      _cue = cue.text;
      if (cue.speak) _say(cue.text!, tMs);
      final names = broke.failed.map((c) => c.name).join(', ');
      debugPrint(
        'ENGINE hold broken at ${hold.seconds.toStringAsFixed(1)} s ($names)'
        '${cue.speak ? '  cue "${cue.text}" spoken' : ''}',
      );
      for (final r in broke.results) {
        debugPrint(
          '  ${r.check.name}: value=${r.value?.toStringAsFixed(3) ?? '-'} '
          '${r.check.kind.name} ${r.limit} -> '
          '${r.passed == null ? 'skipped' : (r.passed! ? 'pass' : 'FAIL')}',
        );
      }
      for (final c in cue.tips) {
        debugPrint('ENGINE tip card: ${c.name} 3 times this set');
      }
    }
    if (hold.state != before) {
      debugPrint('ENGINE hold: ${hold.state.name}');
      if (hold.state == HoldState.holding) _cue = null;
    }
    // Green while holding, red while broken (the live screen's frame colour).
    _lastRepCorrect = switch (hold.state) {
      HoldState.holding => true,
      HoldState.broken => false,
      HoldState.notInPosition => null,
    };
  }

  // The drawn skeleton follows each point with an exponential moving average:
  // drawSmoothing of the newest frame, the rest from the previous drawing.
  // Display only: counting and judging use the measurement layer's own
  // smoothing. Starts fresh whenever the person was out of view.
  static const double drawSmoothing = 0.5;
  // Holds (plank) barely move, so their skeleton is smoothed more: the
  // forearms flat on the floor make ML Kit's arm points jump most.
  static const double holdDrawSmoothing = 0.25;

  Pose _smoothForDrawing(Pose pose) {
    final previous = _pose;
    if (previous == null) return pose;
    final a = _hold != null ? holdDrawSmoothing : drawSmoothing;
    final smoothed = <PoseLandmarkType, PoseLandmark>{};
    pose.landmarks.forEach((type, lm) {
      final p = previous.landmarks[type];
      smoothed[type] = p == null
          ? lm
          : PoseLandmark(
              type: type,
              x: a * lm.x + (1 - a) * p.x,
              y: a * lm.y + (1 - a) * p.y,
              z: lm.z,
              likelihood: lm.likelihood,
            );
    });
    return Pose(landmarks: smoothed);
  }

  // Speaks a cue and logs how long after the frame arrived it was decided
  // (ML Kit plus the engine). CueSpeaker logs when the audio starts.
  void _say(String text, int tMs) {
    debugPrint(
      'CUE decided ${_clock.elapsedMilliseconds - tMs} ms after its frame '
          'arrived: "$text"',
    );
    _speaker.speak(text);
  }

  // Every 5 s: processed and camera frame rates and the average ML Kit time.
  // Clearing inferenceMs here also stops the list growing for the whole set.
  void _logFps() {
    _frames++;
    final elapsedMs = _fpsWatch.elapsedMilliseconds;
    if (elapsedMs < 5000) return;
    final secs = elapsedMs / 1000;
    final ms = _poseService.inferenceMs;
    final mlkitMs = ms.isEmpty ? 0 : ms.reduce((a, b) => a + b) ~/ ms.length;
    debugPrint(
      'ENGINE processed=${(_frames / secs).toStringAsFixed(1)} fps  '
          'camera=${(_cameraFrames / secs).toStringAsFixed(1)} fps  '
          'mlkit=$mlkitMs ms',
    );
    _frames = 0;
    _cameraFrames = 0;
    ms.clear();
    _fpsWatch.reset();
  }

  void _publish() {
    if (_stopped) return;
    _current = WorkoutView(
      personVisible: _personVisible,
      ready: _layer.isReady,
      paused: _manualPause || _autoPaused,
      correct: _correct,
      attempted: _attempted,
      cue: _cue,
      holdSeconds: _hold?.seconds ?? 0,
      lastRepCorrect: _lastRepCorrect,
      correctLeft: _correctLeft,
      correctRight: _correctRight,
      exerciseWarning: _checkMessage,
    );
    _updates.add(_current);
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    final camera = _camera;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black, child: SizedBox.expand());
    }
    final pose = _pose;
    final rotation = _rotation;
    final size = _imageSize;
    Widget? skeleton;
    if (_personVisible &&
        pose != null &&
        rotation != null &&
        size != null &&
        camera != null) {
      skeleton = CustomPaint(
        painter: SkeletonPainter(
          pose: pose,
          imageSize: size,
          rotation: rotation,
          lens: camera.lensDirection,
        ),
      );
    }
    return CameraPreview(controller, child: skeleton);
  }

  @override
  void beginSet() {
    _counter?.reset();
    _hold?.reset();
    _cues.reset();
    _correct = 0;
    _attempted = 0;
    _correctLeft = 0;
    _correctRight = 0;
    _cue = null;
    _lastRepCorrect = null;
    _setReps.clear();
    _check.reset();
    _checkMessage = null;
    _counting = true;
    _publish();
  }

  @override
  List<RepRecord> takeSetReps() {
    final reps = List.of(_setReps);
    _setReps.clear();
    return reps;
  }

  @override
  void pause() {
    _manualPause = true;
    _counter?.reset(keepCount: true); // a half-done rep does not carry over
    _check.reset();
    _checkMessage = null;
    _publish();
  }

  @override
  void resume() {
    // No publish here: _startNextSet() calls resume() before beginSet(), and
    // an update now would carry the old set's counts unpaused. The next
    // processed frame publishes (about 50 ms later).
    _manualPause = false;
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    final controller = _controller;
    _controller = null;
    try {
      if (controller != null && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('ENGINE stopImageStream: $e');
    }
    await controller?.dispose();
    if (!_released.isCompleted) _released.complete(); // camera free for the next
    await _speaker.stop();
    await _poseService.close();
    _clock.stop();
    await _updates.close();
  }
}
