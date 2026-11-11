import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

void main() {
  test('ML Kit landmark order matches the landmark map', () {
    expect(PoseLandmarkType.leftEar.index, 7);
    expect(PoseLandmarkType.leftShoulder.index, 11);
    expect(PoseLandmarkType.leftHip.index, 23);
    expect(PoseLandmarkType.leftHeel.index, 29);
    expect(PoseLandmarkType.rightFootIndex.index, 32);
  });
}
