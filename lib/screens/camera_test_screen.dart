import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../engine/exercise_config.dart';
import '../engine/measurement_layer.dart';
import '../engine/rep_counter.dart';
import '../services/pose_service.dart';
import '../widgets/skeleton_painter.dart';

class CameraTestScreen extends StatefulWidget {
  const CameraTestScreen({super.key});

  @override
  State<CameraTestScreen> createState() => _CameraTestScreenState();
}

class _CameraTestScreenState extends State<CameraTestScreen> {
  final _poseService = PoseService();
  final _fpsWatch = Stopwatch();
  final _clock = Stopwatch(); // t_ms for the engine
  final _layer = MeasurementLayer(squatConfig);
  final _counter = RepCounter.forExercise(squatConfig);
  CameraController? _controller;
  CameraDescription? _camera;
  Pose? _pose;
  InputImageRotation? _rotation;
  Size? _imageSize;
  FrameResult? _frame;
  bool _isPerson = false;
  RepResult? _lastRep;
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
    if (controller == null || camera == null) return;
    final orientation = controller.value.deviceOrientation;
    final poses = await _poseService.process(image, camera, orientation);
    if (poses == null || !mounted) return;
    final pose = poses.isEmpty ? null : poses.first;

    // Engine: measurement layer, then rep counter.
    final wasReady = _layer.isReady;
    final points = PoseService.toPoints(pose);
    final frame = _layer.process(points, tMs);
    if (!wasReady && _layer.isReady) {
      debugPrint(
        'SETUP done: side=${_layer.side!.name} '
        'facing=${_layer.facing} baseline=${_layer.baseline}',
      );
    }
    if (frame.status == FrameStatus.paused) {
      debugPrint('PAUSED: no judgeable frame for 2 s, setup starts again');
      _counter.reset(keepCount: true);
    }
    if (frame.status == FrameStatus.judged) {
      final main = frame.values[squatConfig.mainMeasurement];
      if (main != null) {
        final rep = _counter.update(main, frame.values, tMs);
        if (rep != null) {
          _lastRep = rep;
          debugPrint(
            'REP ${_counter.count}: '
            'deepest=${rep.deepest.toStringAsFixed(1)} '
            'duration=${rep.durationMs} ms',
          );
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
      _isPerson = _layer.hasPerson(points);
    });
  }

  void _resetSet() {
    setState(() {
      _layer.reset();
      _counter.reset();
      _lastRep = null;
    });
  }

  String _infoText() {
    final lines = [
      'FPS: ${_fps.toStringAsFixed(1)}   Pose: ${_isPerson ? 'found' : (_pose == null ? 'none' : 'weak')}',
    ];
    final f = _frame;
    if (f != null) {
      final knee = f.values['knee_angle'];
      lines
        ..add('Status: ${f.status.name}   Side: ${_layer.side?.name ?? '-'}')
        ..add(
          'Knee: ${knee == null ? '-' : knee.toStringAsFixed(0)}   '
          'Stage: ${_counter.stage.name}',
        )
        ..add('Reps: ${_counter.count}');
      final r = _lastRep;
      if (r != null) {
        lines.add(
          'Last rep: deepest ${r.deepest.toStringAsFixed(0)}, '
          '${(r.durationMs / 1000).toStringAsFixed(1)} s',
        );
      }
    }
    return lines.join('\n');
  }

  @override
  void dispose() {
    _controller?.dispose();
    _poseService.close();
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
