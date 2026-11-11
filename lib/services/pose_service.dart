import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../engine/geometry.dart';

class PoseService {
  final PoseDetector _detector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );
  bool _busy = false;
  final List<int> inferenceMs = [];

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// ML Kit pose -> {landmark index: point} for the engine.
  /// No pose gives an empty map, which the engine treats as "no person".
  static Map<int, Pt> toPoints(Pose? pose) {
    if (pose == null) return const <int, Pt>{};
    return {
      for (final e in pose.landmarks.entries)
        e.key.index: Pt(e.value.x, e.value.y, e.value.likelihood),
    };
  }

  /// Rotation ML Kit needs to see the person upright.
  InputImageRotation? rotationFor(
    CameraDescription camera,
    DeviceOrientation o,
  ) {
    final comp = _orientations[o];
    if (comp == null) return null;
    final s = camera.sensorOrientation;
    final deg = camera.lensDirection == CameraLensDirection.front
        ? (s + comp) % 360
        : (s - comp + 360) % 360;
    return InputImageRotationValue.fromRawValue(deg);
  }

  /// Returns null when busy with another frame or when the frame cannot be converted.
  Future<List<Pose>?> process(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation o,
  ) async {
    if (_busy) return null;
    final input = _toInputImage(image, camera, o);
    if (input == null) return null;
    _busy = true;
    final sw = Stopwatch()..start();
    try {
      return await _detector.processImage(input);
    } finally {
      inferenceMs.add(sw.elapsedMilliseconds);
      _busy = false;
    }
  }

  InputImage? _toInputImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation o,
  ) {
    final rotation = rotationFor(camera, o);
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        format != InputImageFormat.nv21 ||
        image.planes.length != 1) {
      return null;
    }
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> close() => _detector.close();
}
