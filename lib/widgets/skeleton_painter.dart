import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class SkeletonPainter extends CustomPainter {
  SkeletonPainter({
    required this.pose,
    required this.imageSize,
    required this.rotation,
    required this.lens,
    this.minLikelihood = 0.5,
  });

  final Pose pose;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lens;
  final double minLikelihood;

  static const _bones = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  Offset _toCanvas(PoseLandmark lm, Size canvas) {
    final sideways =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final w = sideways ? imageSize.height : imageSize.width;
    final h = sideways ? imageSize.width : imageSize.height;
    var x = lm.x * canvas.width / w;
    final y = lm.y * canvas.height / h;
    if (lens == CameraLensDirection.front) x = canvas.width - x;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bonePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;
    for (final b in _bones) {
      final a = pose.landmarks[b[0]];
      final c = pose.landmarks[b[1]];
      if (a == null || c == null) continue;
      canvas.drawLine(_toCanvas(a, size), _toCanvas(c, size), bonePaint);
    }
    for (final lm in pose.landmarks.values) {
      final ok = lm.likelihood >= minLikelihood;
      canvas.drawCircle(
        _toCanvas(lm, size),
        5,
        Paint()..color = ok ? Colors.green : Colors.red,
      );
    }
  }

  @override
  bool shouldRepaint(SkeletonPainter old) => old.pose != pose;
}
