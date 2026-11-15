// Measurement layer (roadmap Part 4), following the Shared Formula Document
// (v0.4.2): setup window -> confidence check -> body length -> plausibility
// -> measurements -> smoothing. Keep the order the same as Member C's
// tools/measurements.py.

import 'constants.dart';
import 'exercise_config.dart';
import 'geometry.dart';
import 'landmarks.dart';
import 'smoothing.dart';

enum FrameStatus {
  /// Collecting the setup window (side, facing, baseline, setup lengths).
  setup,

  /// Measured; [FrameResult.values] holds the smoothed values.
  judged,

  /// Not judgeable (low confidence, no person, body too small, or an
  /// impossible angle or segment length).
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

/// A thigh or shin and its median length during setup (formula v0.4).
typedef SetupSegment = ({int a, int b, double length});

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
  final List<SetupSegment> _segments = [];
  int? _setupStartMs;
  int? _lastJudgedMs;

  /// Chosen once per set in the setup window. Null until setup finishes.
  Side? side;
  int facing = 1;

  /// Median y per joint and side, e.g. 'heel_left', plus 'floor'.
  final Map<String, double> baseline = {};

  bool get isReady => side != null;

  /// Setup thigh and shin lengths, for the plausibility check.
  List<SetupSegment> get setupSegments => List.unmodifiable(_segments);

  bool _passes(Map<int, Pt> lm, Joint j, Side s) {
    final p = lm[landmarkIndex(j, s)];
    return p != null && p.c >= minConfidence;
  }

  /// True when the required joints pass the confidence check on at least
  /// one side, and the both-sides joints pass on both sides. Weak false
  /// detections (for example on a chair) fail this.
  bool hasPerson(Map<int, Pt> lm) {
    final bothOk = config.bothSidesJoints.every(
      (j) => _passes(lm, j, Side.left) && _passes(lm, j, Side.right),
    );
    final sideOk = Side.values.any(
      (s) => config.requiredJoints.every((j) => _passes(lm, j, s)),
    );
    return bothOk && sideOk;
  }

  /// Start a new set: forget side, facing, baseline, setup lengths and
  /// smoothing.
  void reset() {
    side = null;
    facing = 1;
    baseline.clear();
    _segments.clear();
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
    if (bodyLen == null) return _notJudged(tMs);

    final ctx = MeasurementContext(lm, side!, facing, bodyLen, baseline);
    final raw = {
      for (final name in config.measurements)
        name: measurementRegistry[name]!(ctx),
    };

    // v0.4: an impossible joint angle makes the whole frame unjudgeable.
    final implausible = raw.entries.any(
      (e) =>
          e.key.endsWith('_angle') &&
          !e.value.isNaN &&
          e.value < plausibleMinAngleDeg,
    );
    if (implausible) return _notJudged(tMs);

    if (tMs - _lastJudgedMs! > smoothResetMs) {
      for (final s in _smoothers.values) {
        s.reset();
      }
    }
    final values = <String, double>{};
    for (final e in raw.entries) {
      if (e.value.isNaN) continue; // unjudgeable for this measurement only
      values[e.key] = _smoothers[e.key]!.add(e.value);
    }
    _lastJudgedMs = tMs;
    return FrameResult(FrameStatus.judged, tMs, values);
  }

  /// A frame that can't be judged: nothing is smoothed and _lastJudgedMs
  /// stays the same. After lowConfPauseMs of these, pause and set up again.
  FrameResult _notJudged(int tMs) {
    if (tMs - _lastJudgedMs! >= lowConfPauseMs) {
      reset();
      return FrameResult(FrameStatus.paused, tMs);
    }
    return FrameResult(FrameStatus.skipped, tMs);
  }

  /// Body length if every required joint passes and every setup segment is
  /// a plausible length; otherwise null.
  double? _judgeableBodyLength(Map<int, Pt> lm) {
    final joints = {...config.requiredJoints, Joint.shoulder, Joint.hip};
    for (final j in joints) {
      if (!_passes(lm, j, side!)) return null;
    }
    for (final j in config.bothSidesJoints) {
      if (!_passes(lm, j, Side.left) || !_passes(lm, j, Side.right)) {
        return null;
      }
    }
    final len = bodyLength(
      lm[landmarkIndex(Joint.shoulder, side!)]!,
      lm[landmarkIndex(Joint.hip, side!)]!,
    );
    if (len < minBodyLengthPx) return null;

    // v0.4: a thigh or shin far from its setup length is impossible.
    for (final seg in _segments) {
      final pa = lm[seg.a], pb = lm[seg.b];
      if (pa == null || pb == null) return null;
      if (!plausibleLength(segmentLength(pa, pb), seg.length)) return null;
    }
    return len;
  }

  // Setup window: the first baselineMs in which a person passes hasPerson
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
    // v0.4: the side whose required joints pass the confidence check in more
    // setup frames; if equal, the higher mean confidence; if still equal, left.
    double passRate(Side s) =>
        _setupFrames
            .where((f) => config.requiredJoints.every((j) => _passes(f, j, s)))
            .length /
        _setupFrames.length;

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

    final rightPass = passRate(Side.right), leftPass = passRate(Side.left);
    final chosen =
        rightPass > leftPass ||
            (rightPass == leftPass &&
                meanConfidence(Side.right) > meanConfidence(Side.left))
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

    // v0.4: setup thigh and shin lengths of every leg whose joints are
    // required (the chosen side's required joints plus the both-sides joints).
    _segments.clear();
    for (final s in Side.values) {
      final req = {
        ...config.bothSidesJoints,
        if (s == chosen) ...config.requiredJoints,
      };
      for (final (j1, j2) in const [
        (Joint.hip, Joint.knee),
        (Joint.knee, Joint.ankle),
      ]) {
        if (!req.contains(j1) || !req.contains(j2)) continue;
        final a = landmarkIndex(j1, s), b = landmarkIndex(j2, s);
        final lengths = [
          for (final f in _setupFrames)
            if (f[a] != null && f[b] != null) segmentLength(f[a]!, f[b]!),
        ];
        if (lengths.isNotEmpty) {
          _segments.add((a: a, b: b, length: median(lengths)));
        }
      }
    }

    side = chosen;
    _lastJudgedMs = tMs;
    _setupFrames.clear();
  }
}
