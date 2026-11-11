// Measurement layer (roadmap Part 4), following the Shared Formula Document:
// setup window -> confidence check -> body length -> measurements -> smoothing.

import 'constants.dart';
import 'exercise_config.dart';
import 'geometry.dart';
import 'landmarks.dart';
import 'smoothing.dart';

enum FrameStatus {
  /// Collecting the setup window (side, facing, baseline).
  setup,

  /// Measured; [FrameResult.values] holds the smoothed values.
  judged,

  /// Not judgeable (low confidence, no person, or body too small).
  skipped,

  /// No judgeable frame for lowConfPauseMs. Setup starts again.
  paused,
}

class FrameResult {
  const FrameResult(this.status, this.tMs, [this.values = const {}]);
  final FrameStatus status;
  final int tMs;
  final Map<String, double> values;
}

/// What a measurement function can use for one frame.
class MeasurementContext {
  MeasurementContext(
    this.lm,
    this.side,
    this.facing,
    this.bodyLen,
    this.baseline,
  );
  final Map<int, Pt> lm;
  final Side side;
  final int facing;
  final double bodyLen;
  final Map<String, double> baseline;

  /// Point of a joint on the chosen side, or on [s] if given.
  Pt p(Joint j, [Side? s]) => lm[landmarkIndex(j, s ?? side)]!;
}

typedef MeasureFn = double Function(MeasurementContext c);

/// Measurement catalog. Names match the Shared Formula Document.
/// Add the other exercises' measurements here as their owners need them.
final Map<String, MeasureFn> measurementRegistry = {
  'knee_angle': (c) =>
      jointAngle(c.p(Joint.hip), c.p(Joint.knee), c.p(Joint.ankle)),
  'hip_angle': (c) =>
      jointAngle(c.p(Joint.shoulder), c.p(Joint.hip), c.p(Joint.knee)),
  'torso_lean': (c) => lean(c.p(Joint.shoulder), c.p(Joint.hip)),
  'heel_lift': (c) {
    final heel = c.p(Joint.heel);
    final base = c.baseline['heel_${c.side.name}'];
    // Heel is not a required joint, so skip this measurement when unsure.
    if (heel.c < minConfidence || base == null) return double.nan;
    return heightAbove(base, heel.y, c.bodyLen);
  },
};

class MeasurementLayer {
  MeasurementLayer(this.config) {
    for (final name in config.measurements) {
      if (!measurementRegistry.containsKey(name)) {
        throw ArgumentError('Unknown measurement: $name');
      }
      _smoothers[name] = MovingAverage(
        name.startsWith('jump_rise') ? smoothNJump : smoothN,
      );
    }
  }

  final ExerciseConfig config;
  final Map<String, MovingAverage> _smoothers = {};
  final List<Map<int, Pt>> _setupFrames = [];
  int? _setupStartMs;
  int? _lastJudgedMs;

  /// Chosen once per set in the setup window. Null until setup finishes.
  Side? side;
  int facing = 1;

  /// Median y per joint and side, e.g. 'heel_left', plus 'floor'.
  final Map<String, double> baseline = {};

  bool get isReady => side != null;

  /// True when the required joints pass the confidence check on at least
  /// one side. Weak false detections (for example on a chair) fail this.
  bool hasPerson(Map<int, Pt> lm) {
    for (final s in Side.values) {
      final ok = config.requiredJoints.every((j) {
        final p = lm[landmarkIndex(j, s)];
        return p != null && p.c >= minConfidence;
      });
      if (ok) return true;
    }
    return false;
  }

  /// Start a new set: forget side, facing, baseline and smoothing.
  void reset() {
    side = null;
    facing = 1;
    baseline.clear();
    _setupFrames.clear();
    _setupStartMs = null;
    _lastJudgedMs = null;
    for (final s in _smoothers.values) {
      s.reset();
    }
  }

  /// Process one frame. [lm] maps landmark index to point; empty = no person.
  FrameResult process(Map<int, Pt> lm, int tMs) {
    if (side == null) return _setup(lm, tMs);

    final bodyLen = _judgeableBodyLength(lm);
    if (bodyLen == null) {
      if (tMs - _lastJudgedMs! >= lowConfPauseMs) {
        reset();
        return FrameResult(FrameStatus.paused, tMs);
      }
      return FrameResult(FrameStatus.skipped, tMs);
    }

    if (tMs - _lastJudgedMs! > smoothResetMs) {
      for (final s in _smoothers.values) {
        s.reset();
      }
    }

    final ctx = MeasurementContext(lm, side!, facing, bodyLen, baseline);
    final values = <String, double>{};
    for (final name in config.measurements) {
      final raw = measurementRegistry[name]!(ctx);
      if (raw.isNaN) continue; // unjudgeable for this measurement only
      values[name] = _smoothers[name]!.add(raw);
    }
    _lastJudgedMs = tMs;
    return FrameResult(FrameStatus.judged, tMs, values);
  }

  /// Body length if every required joint passes, otherwise null.
  double? _judgeableBodyLength(Map<int, Pt> lm) {
    final joints = {...config.requiredJoints, Joint.shoulder, Joint.hip};
    for (final j in joints) {
      final p = lm[landmarkIndex(j, side!)];
      if (p == null || p.c < minConfidence) return null;
    }
    final len = bodyLength(
      lm[landmarkIndex(Joint.shoulder, side!)]!,
      lm[landmarkIndex(Joint.hip, side!)]!,
    );
    return len < minBodyLengthPx ? null : len;
  }

  // Setup window: the first baselineMs in which a person is detected
  // (the rule for recorded videos). Once Member B's countdown exists,
  // call reset() when its last second starts instead.
  FrameResult _setup(Map<int, Pt> lm, int tMs) {
    if (!hasPerson(lm)) {
      _setupFrames.clear();
      _setupStartMs = null;
      return FrameResult(FrameStatus.setup, tMs);
    }
    _setupStartMs ??= tMs;
    _setupFrames.add(lm);
    if (tMs - _setupStartMs! >= baselineMs) _finishSetup(tMs);
    return FrameResult(FrameStatus.setup, tMs);
  }

  void _finishSetup(int tMs) {
    double meanConfidence(Side s) {
      var total = 0.0;
      for (final f in _setupFrames) {
        var sum = 0.0;
        for (final j in config.requiredJoints) {
          sum += f[landmarkIndex(j, s)]?.c ?? 0.0;
        }
        total += sum / config.requiredJoints.length;
      }
      return total / _setupFrames.length;
    }

    // Ties go to the left side.
    final chosen = meanConfidence(Side.right) > meanConfidence(Side.left)
        ? Side.right
        : Side.left;

    // Facing: standing = toes vs heel, floor = shoulder vs hip.
    final standing = config.posture == Posture.standing;
    final diffs = <double>[];
    for (final f in _setupFrames) {
      final a =
          f[landmarkIndex(standing ? Joint.footIndex : Joint.shoulder, chosen)];
      final b = f[landmarkIndex(standing ? Joint.heel : Joint.hip, chosen)];
      if (a != null && b != null) diffs.add(a.x - b.x);
    }
    facing = diffs.isEmpty || median(diffs) >= 0 ? 1 : -1;

    // Baseline: median y of each ankle and heel; floor = mean heel baseline.
    for (final s in Side.values) {
      for (final j in [Joint.ankle, Joint.heel]) {
        final ys = [
          for (final f in _setupFrames)
            if (f[landmarkIndex(j, s)] != null) f[landmarkIndex(j, s)]!.y,
        ];
        if (ys.isNotEmpty) baseline['${j.name}_${s.name}'] = median(ys);
      }
    }
    final hl = baseline['heel_left'], hr = baseline['heel_right'];
    if (hl != null && hr != null) baseline['floor'] = (hl + hr) / 2;

    side = chosen;
    _lastJudgedMs = tMs;
    _setupFrames.clear();
  }
}
