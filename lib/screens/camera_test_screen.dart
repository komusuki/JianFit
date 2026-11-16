import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../engine/cue_manager.dart';
import '../engine/form_judge.dart';
import '../engine/measurement_layer.dart';
import '../engine/rep_counter.dart';
import '../models/exercise_definition.dart';
import '../models/strictness.dart';
import '../services/cue_speaker.dart';
import '../services/exercise_loader.dart';
import '../services/pose_service.dart';
import '../services/settings_service.dart';
import '../widgets/skeleton_painter.dart';

class CameraTestScreen extends StatefulWidget {
  const CameraTestScreen({super.key, this.exerciseId = 'bodyweight_squat'});

  /// Which file in assets/exercises/ to test.
  final String exerciseId;

  @override
  State<CameraTestScreen> createState() => _CameraTestScreenState();
}

class _CameraTestScreenState extends State<CameraTestScreen> {
  final _poseService = PoseService();
  final _fpsWatch = Stopwatch();
  final _clock = Stopwatch(); // t_ms for the engine
  final _cues = CueManager();
  final _speaker = CueSpeaker();
  // Set once the exercise file is loaded.
  ExerciseDefinition? _exercise;
  MeasurementLayer? _layer;
  RepCounter? _counter;
  CameraController? _controller;
  CameraDescription? _camera;
  Pose? _pose;
  InputImageRotation? _rotation;
  Size? _imageSize;
  FrameResult? _frame;
  bool _isPerson = false;
  RepResult? _lastRep;
  RepVerdict? _lastVerdict;
  String? _cue; // shown on screen; null after a correct rep
  Strictness _strictness = Strictness.standard;
  String _status = 'Starting camera...';
  int _frames = 0;
  int _cameraFrames = 0;
  CameraImage? _pending;
  int _pendingMs = 0;
  bool _processing = false;
  double _fps = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final loaded = await ExerciseLoader.loadAll();
    final exercise = loaded.exercises[widget.exerciseId];
    if (exercise == null) {
      if (!mounted) return;
      setState(() {
        _status =
            'Could not load ${widget.exerciseId}.json\n'
            '${loaded.errors.join('\n')}';
      });
      return;
    }
    _exercise = exercise;
    _layer = MeasurementLayer(exercise.config);
    _counter = RepCounter.forExercise(exercise.config);
    _strictness = await SettingsService.loadStrictness(); // Member B's setting
    _cues.voiceOn = await SettingsService.loadVoiceOn(); // Member B's setting
    await _speaker.init();
    debugPrint(
      'EXERCISE loaded: ${exercise.id} '
      '(${loaded.exercises.length} file(s), ${loaded.errors.length} error(s))',
    );

    if (!(await Permission.camera.request()).isGranted) {
      setState(() => _status = 'Camera permission denied');
      return;
    }
    final cameras = await availableCameras();
    _camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      _camera!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await controller.initialize();
    _controller = controller;
    await WakelockPlus.enable();
    _fpsWatch.start();
    _clock.start();
    await controller.startImageStream(_onFrame);
    if (mounted) setState(() => _status = '');
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
    while (image != null && mounted) {
      _pending = null;
      await _handle(image, tMs);
      image = _pending;
      tMs = _pendingMs;
    }
    _processing = false;
  }

  Future<void> _handle(CameraImage image, int tMs) async {
    final controller = _controller;
    final camera = _camera;
    final layer = _layer;
    final counter = _counter;
    final exercise = _exercise;
    if (controller == null ||
        camera == null ||
        layer == null ||
        counter == null ||
        exercise == null) {
      return;
    }
    final orientation = controller.value.deviceOrientation;
    final poses = await _poseService.process(image, camera, orientation);
    if (poses == null || !mounted) return;
    final pose = poses.isEmpty ? null : poses.first;

    // Engine: measurement layer, then rep counter.
    final wasReady = layer.isReady;
    final points = PoseService.toPoints(pose);
    final frame = layer.process(points, tMs);
    if (!wasReady && layer.isReady) {
      debugPrint(
        'SETUP done: side=${layer.side!.name} '
        'facing=${layer.facing} baseline=${layer.baseline}',
      );
    }
    if (frame.status == FrameStatus.paused) {
      debugPrint('PAUSED: no judgeable frame for 2 s, setup starts again');
      counter.reset(keepCount: true);
    }
    if (frame.status == FrameStatus.judged) {
      final main = frame.values[exercise.config.mainMeasurement];
      if (main != null) {
        final rep = counter.update(main, frame.values, tMs);
        if (rep != null) {
          final verdict = judgeRep(rep, exercise.formChecks, _strictness);
          final cue = _cues.onRep(verdict, tMs);
          if (cue.speak) _speaker.speak(cue.text!);
          _cue = cue.text;
          _lastRep = rep;
          _lastVerdict = verdict;
          debugPrint(
            'REP ${counter.count}: '
            'deepest=${rep.deepest.toStringAsFixed(1)} '
            'duration=${rep.durationMs} ms  '
            '${_verdictText(verdict)}',
          );
          if (cue.text != null) {
            debugPrint(
              '  CUE: "${cue.text}" ${cue.speak ? 'spoken' : 'shown only'}',
            );
          }
          for (final c in cue.tips) {
            debugPrint(
              '  TIP CARD: ${c.name} 3 times this set '
              '(demo clip: ${exercise.demoClip ?? 'none'})',
            );
          }
          for (final r in verdict.results) {
            debugPrint(
              '  ${r.check.name}: value=${r.value?.toStringAsFixed(3) ?? '-'} '
              '${r.check.kind.name} ${r.limit} -> '
              '${r.passed == null ? 'skipped' : (r.passed! ? 'pass' : 'FAIL')}',
            );
          }
        }
      }
    }

    _frames++;
    if (_fpsWatch.elapsedMilliseconds >= 5000) {
      final secs = _fpsWatch.elapsedMilliseconds / 1000;
      final ms = _poseService.inferenceMs;
      final avgMs = ms.isEmpty ? 0 : ms.reduce((a, b) => a + b) ~/ ms.length;
      _fps = _frames / secs;
      debugPrint(
        'camera=${(_cameraFrames / secs).toStringAsFixed(1)} fps  '
        'processed=${_fps.toStringAsFixed(1)} fps  mlkit=$avgMs ms',
      );
      _frames = 0;
      _cameraFrames = 0;
      ms.clear();
      _fpsWatch.reset();
    }

    setState(() {
      _pose = pose;
      _frame = frame;
      _rotation = _poseService.rotationFor(camera, orientation);
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      _isPerson = layer.hasPerson(points);
    });
  }

  void _resetSet() {
    setState(() {
      _layer?.reset();
      _counter?.reset();
      _lastRep = null;
      _lastVerdict = null;
      _cues.reset();
      _cue = null;
    });
  }

  /// "correct", or "attempted (failed checks)" plus the top cue.
  static String _verdictText(RepVerdict v) {
    if (v.correct) return 'correct';
    final names = v.failed.map((c) => c.name).join(', ');
    return 'attempted ($names) cue: ${v.topFailed!.cue}';
  }

  String _infoText() {
    final lines = [
      'FPS: ${_fps.toStringAsFixed(1)}   Pose: ${_isPerson ? 'found' : (_pose == null ? 'none' : 'weak')}',
    ];
    final f = _frame;
    final exercise = _exercise;
    final counter = _counter;
    if (f != null && exercise != null && counter != null) {
      final mainName = exercise.config.mainMeasurement;
      final main = f.values[mainName];
      lines
        ..add('${exercise.info.name}   Strictness: ${_strictness.name}')
        ..add('Voice: ${_cues.voiceOn ? 'on' : 'off'}   Cue: ${_cue ?? '-'}')
        ..add('Status: ${f.status.name}   Side: ${_layer?.side?.name ?? '-'}')
        ..add(
          '$mainName: ${main == null ? '-' : main.toStringAsFixed(0)}   '
          'Stage: ${counter.stage.name}',
        )
        ..add('Reps: ${counter.count}');
      final r = _lastRep;
      final v = _lastVerdict;
      if (r != null && v != null) {
        lines
          ..add(
            'Last rep: deepest ${r.deepest.toStringAsFixed(0)}, '
            '${(r.durationMs / 1000).toStringAsFixed(1)} s',
          )
          ..add(_verdictText(v));
      }
    }
    return lines.join('\n');
  }

  @override
  void dispose() {
    _controller?.dispose();
    _poseService.close();
    _speaker.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Scaffold(body: Center(child: Text(_status)));
    }
    final canDraw =
        _isPerson && _pose != null && _rotation != null && _imageSize != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: CameraPreview(
              c,
              child: canDraw
                  ? CustomPaint(
                      painter: SkeletonPainter(
                        pose: _pose!,
                        imageSize: _imageSize!,
                        rotation: _rotation!,
                        lens: _camera!.lensDirection,
                      ),
                    )
                  : null,
            ),
          ),
          Positioned(
            top: 40,
            left: 16,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(8),
              child: Text(
                _infoText(),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            right: 16,
            child: ElevatedButton(
              onPressed: _resetSet,
              child: const Text('Reset set'),
            ),
          ),
        ],
      ),
    );
  }
}
