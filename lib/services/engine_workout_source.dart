import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../engine/cue_manager.dart';
import '../engine/form_judge.dart';
import '../engine/measurement_layer.dart';
import '../engine/rep_counter.dart';
import '../models/exercise_definition.dart';
import '../models/strictness.dart';
import '../models/workout_view.dart';
import '../widgets/skeleton_painter.dart';
import 'cue_speaker.dart';
import 'pose_service.dart';
import 'settings_service.dart';
import 'workout_source.dart';

// The real workout source (Day 8). Owner: Member A.
// Front camera and ML Kit, then the engine in the same order as
// CameraTestScreen: measurement layer, rep counter (reset on an automatic
// pause), form judge, cue manager. Drives Member B's setup check and live
// workout screens through the WorkoutSource contract.
// Before beginSet() only the measurement layer runs (setup and ready).
// Hold exercises are not timed yet: the hold timer comes on Day 9.
class EngineWorkoutSource implements WorkoutSource {
  EngineWorkoutSource(this.exercise, this.strictness)
    : _layer = MeasurementLayer(exercise.config),
      _counter = RepCounter.forExercise(exercise.config);

  final ExerciseDefinition exercise;
  final Strictness strictness;

  final MeasurementLayer _layer;
  final RepCounter _counter;
  final _cues = CueManager();
  final _speaker = CueSpeaker();
  final _poseService = PoseService();
  final _clock = Stopwatch(); // t_ms for the engine
  final _fpsWatch = Stopwatch();
  final _updates = StreamController<WorkoutView>.broadcast();
  WorkoutView _current = const WorkoutView();

  CameraController? _controller;
  CameraDescription? _camera;
  CameraImage? _pending;
  int _pendingMs = 0;
  bool _processing = false;
  bool _stopped = false;
  int _frames = 0;

  // The latest processed frame, for the skeleton.
  Pose? _pose;
  InputImageRotation? _rotation;
  Size? _imageSize;
  bool _personVisible = false;

  bool _counting = false;
  bool _manualPause = false;
  bool _autoPaused = false;
  int _correct = 0;
  int _attempted = 0;
  String? _cue;
  bool? _lastRepCorrect;

  @override
  Stream<WorkoutView> get updates => _updates.stream;

  @override
  WorkoutView get current => _current;

  @override
  Future<void> start() async {
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
      _counter.reset(keepCount: true);
      debugPrint('ENGINE paused: no judgeable frame for 2 s');
    } else if (frame.status == FrameStatus.judged) {
      _autoPaused = false;
      if (_counting && !_manualPause) _count(frame, tMs);
    }

    _pose = pose;
    _rotation = _poseService.rotationFor(camera, orientation);
    _imageSize = Size(image.width.toDouble(), image.height.toDouble());
    _personVisible = _layer.hasPerson(points);
    _logFps();
    _publish();
  }

  void _count(FrameResult frame, int tMs) {
    final main = frame.values[exercise.config.mainMeasurement];
    if (main == null) return;
    final rep = _counter.update(main, frame.values, tMs);
    if (rep == null) return;
    final verdict = judgeRep(rep, exercise.formChecks, strictness);
    _attempted++;
    if (verdict.correct) _correct++;
    _lastRepCorrect = verdict.correct;
    final cue = _cues.onRep(verdict, tMs);
    _cue = cue.text;
    if (cue.speak) _speaker.speak(cue.text!);
    final names = verdict.failed.map((c) => c.name).join(', ');
    final result = verdict.correct ? 'correct' : 'attempted ($names)';
    final said = cue.text == null
        ? ''
        : '  cue "${cue.text}" ${cue.speak ? 'spoken' : 'shown only'}';
    debugPrint('ENGINE rep $_attempted: $result$said');
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

  void _logFps() {
    _frames++;
    if (_fpsWatch.elapsedMilliseconds < 5000) return;
    final fps = _frames * 1000 / _fpsWatch.elapsedMilliseconds;
    debugPrint('ENGINE processed=${fps.toStringAsFixed(1)} fps');
    _frames = 0;
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
      lastRepCorrect: _lastRepCorrect,
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
    _counter.reset();
    _cues.reset();
    _correct = 0;
    _attempted = 0;
    _cue = null;
    _lastRepCorrect = null;
    _counting = true;
    _publish();
  }

  @override
  void pause() {
    _manualPause = true;
    _counter.reset(keepCount: true); // a half-done rep does not carry over
    _publish();
  }

  @override
  void resume() {
    _manualPause = false;
    _publish();
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
    await _speaker.stop();
    await _poseService.close();
    _clock.stop();
    await _updates.close();
  }
}
