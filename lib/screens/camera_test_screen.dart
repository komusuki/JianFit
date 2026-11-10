import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  CameraController? _controller;
  CameraDescription? _camera;
  Pose? _pose;
  InputImageRotation? _rotation;
  Size? _imageSize;
  String _status = 'Starting camera...';
  int _frames = 0;
  int _cameraFrames = 0;
  CameraImage? _pending;
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
    await controller.startImageStream(_onFrame);
    if (mounted) setState(() => _status = '');
  }

  void _onFrame(CameraImage image) {
    _cameraFrames++;
    if (_processing) {
      _pending = image; // keep only the newest frame
      return;
    }
    _processLoop(image);
  }

  Future<void> _processLoop(CameraImage first) async {
    _processing = true;
    CameraImage? image = first;
    while (image != null && mounted) {
      _pending = null;
      await _handle(image);
      image = _pending;
    }
    _processing = false;
  }

  Future<void> _handle(CameraImage image) async {
    final controller = _controller;
    final camera = _camera;
    if (controller == null || camera == null) return;
    final orientation = controller.value.deviceOrientation;
    final poses = await _poseService.process(image, camera, orientation);
    if (poses == null || !mounted) return;
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
      _pose = poses.isEmpty ? null : poses.first;
      _rotation = _poseService.rotationFor(camera, orientation);
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());
    });
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
    final canDraw = _pose != null && _rotation != null && _imageSize != null;
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
                'FPS: ${_fps.toStringAsFixed(1)}   Pose: ${_pose == null ? 'none' : 'found'}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
