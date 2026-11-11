import 'package:test/test.dart';
import 'package:jianfit/engine/exercise_config.dart';
import 'package:jianfit/engine/geometry.dart';
import 'package:jianfit/engine/landmarks.dart';
import 'package:jianfit/engine/measurement_layer.dart';

/// A person standing straight, facing right. Left side is more confident.
Map<int, Pt> standingFrame() {
  final m = <int, Pt>{};
  void put(Joint j, double x, double y) {
    m[landmarkIndex(j, Side.left)] = Pt(x, y, 0.9);
    m[landmarkIndex(j, Side.right)] = Pt(x, y, 0.6);
  }

  put(Joint.shoulder, 100, 100);
  put(Joint.hip, 100, 300);
  put(Joint.knee, 100, 500);
  put(Joint.ankle, 100, 700);
  put(Joint.heel, 90, 710);
  put(Joint.footIndex, 130, 710);
  return m;
}

void main() {
  test('setup picks side, facing and baseline, then judges frames', () {
    final layer = MeasurementLayer(squatConfig);
    for (var t = 0; t < 1000; t += 100) {
      expect(layer.process(standingFrame(), t).status, FrameStatus.setup);
    }
    expect(layer.process(standingFrame(), 1000).status, FrameStatus.setup);
    expect(layer.side, Side.left);
    expect(layer.facing, 1);
    expect(layer.baseline['heel_left'], 710);
    expect(layer.baseline['floor'], 710);

    final f = layer.process(standingFrame(), 1100);
    expect(f.status, FrameStatus.judged);
    expect(f.values['knee_angle'], closeTo(180, 0.01));
    expect(f.values['hip_angle'], closeTo(180, 0.01));
    expect(f.values['torso_lean'], closeTo(0, 0.01));
    expect(f.values['heel_lift'], closeTo(0, 0.01));
  });

  test('pauses after 2000 ms without a judgeable frame', () {
    final layer = MeasurementLayer(squatConfig);
    for (var t = 0; t <= 1000; t += 100) {
      layer.process(standingFrame(), t);
    }
    expect(layer.process(standingFrame(), 1100).status, FrameStatus.judged);
    expect(layer.process(const {}, 2000).status, FrameStatus.skipped);
    expect(layer.process(const {}, 3100).status, FrameStatus.paused);
    expect(layer.isReady, isFalse);
  });

  test('setup ignores weak detections (for example a chair)', () {
    final layer = MeasurementLayer(squatConfig);
    final weak = {
      for (final e in standingFrame().entries)
        e.key: Pt(e.value.x, e.value.y, 0.2),
    };
    for (var t = 0; t <= 2000; t += 100) {
      layer.process(weak, t);
    }
    expect(layer.isReady, isFalse);
  });
}
