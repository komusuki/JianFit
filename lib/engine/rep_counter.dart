// Rep counter (roadmap Part 5): one main measurement drives a state machine
// with two thresholds and a gap between them, so jitter is not a rep.
//
// Roadmap stages -> this code:
//   Ready      -> RepStage.ready
//   Going Down -> RepStage.goingDown
//   Bottom     -> the moment the value turns back by repTurnaroundDeg
//   Coming Up  -> RepStage.comingUp
//   Complete   -> the moment update() returns a RepResult
//
// Jump squat (Day 9, when jumpLimit is set): a jump is both ankles rising
// more than jumpLimit above their lowest point before takeoff (so the setup
// baseline cancels out). Landing is when they are no longer both above it.
// The rep completes landingWindowMs after landing, and landing_knee_min is the
// smallest knee angle in that window. The deepest value stays the one from
// before the jump. Without a jump, the rep completes jumpWaitMs after the knee
// is back up. Each rep also reports jump_height.
// Back-to-back jumps: a takeoff inside the landing window completes the rep
// right there, and the next rep starts in the air (its deepest value is the
// dip after the landing). After a rep that completed while the knee was still
// bent, a new rep only starts once the knee has been back up, or at the next
// takeoff, so standing up slowly after a landing is not a rep.
// A takeoff (and jump_height) only counts while the knee is extended past
// startThreshold: feet can't leave the floor in a deep bend, and the ankle
// points drift up at the bottom of a squat.
//
// Heel rise (v0.6, when the frames carry heel_lift): heel_rise = heel_lift at
// the deepest frame minus heel_lift when the rep started. Measured from the
// rep's own start, it cancels the heel baseline drifting between reps
// (standing a little closer or farther, the heel point sliding).
//
// Lunges (Day 9): update() takes the frame's front leg, and each rep is
// credited to the leg in front at its deepest frame (RepResult.leg).

import 'dart:math';

import 'constants.dart';
import 'exercise_config.dart';
import 'landmarks.dart';

enum RepStage { ready, goingDown, comingUp }

class RepResult {
  const RepResult({
    required this.deepest,
    required this.atDeepest,
    required this.durationMs,
    required this.endMs,
    this.minDuring = const {},
    this.maxDuring = const {},
    this.leg,
  });

  /// Deepest value of the main measurement (minimum for dip, maximum for hill).
  final double deepest;

  /// All smoothed measurements at the deepest frame (for the form judge).
  final Map<String, double> atDeepest;

  /// From leaving Ready to Complete.
  final int durationMs;
  final int endMs;

  /// Lowest and highest smoothed value of each measurement during the rep,
  /// from leaving Ready to Complete (for form checks with "when": throughout).
  final Map<String, double> minDuring;
  final Map<String, double> maxDuring;

  /// Lunges: the front leg at the deepest frame. Null for other exercises.
  final Side? leg;
}

class RepCounter {
  RepCounter({
    required this.direction,
    required this.startThreshold,
    required this.completeThreshold,
    this.turnaround = repTurnaroundDeg,
    this.jumpLimit,
  }) : assert(
         direction == Direction.dip
             ? completeThreshold > startThreshold
             : completeThreshold < startThreshold,
       );

  /// Throws for holds (no rep fields): they use HoldTimer instead.
  factory RepCounter.forExercise(ExerciseConfig c) => RepCounter(
    direction: c.direction!,
    startThreshold: c.startThreshold!,
    completeThreshold: c.completeThreshold!,
    jumpLimit: c.jumpLimit,
  );

  final Direction direction;
  final double startThreshold;
  final double completeThreshold;
  final double turnaround;
  final double? jumpLimit;

  RepStage stage = RepStage.ready;
  int count = 0;
  double? _extreme;
  Map<String, double> _atExtreme = const {};
  final Map<String, double> _min = {};
  final Map<String, double> _max = {};
  int _startMs = 0;
  Side? _legAtExtreme;
  double? _startHeel; // heel_lift when the rep started

  // Jump squat state for the rep in progress.
  double? _riseStartL, _riseStartR; // lowest jump_rise values before the jump
  double _jumpHeight = 0;
  bool _airborne = false;
  bool _jumped = false;
  int? _landedMs;
  double? _landingMin;
  int? _backUpMs; // no jump yet: when the knee came back up
  Map<String, double> _landingAt = const {}; // values at landing_knee_min
  double? _lowL, _lowR; // lowest ankle values since landing

  // Jump squat, between reps: what a takeoff with no rep in progress starts
  // from.
  bool _armed = true; // false: the knee must come back up first
  int? _readyMs; // start time for a rep that begins in the air
  double? _readyExtreme; // deepest main value since then
  Map<String, double> _readyAt = const {};
  double? _readyL, _readyR; // lowest ankle values since then

  bool get _dip => direction == Direction.dip;
  bool _started(double v) => _dip ? v < startThreshold : v > startThreshold;
  bool _returned(double v) =>
      _dip ? v > completeThreshold : v < completeThreshold;
  bool _deeper(double v) => _deeperThan(v, _extreme!);
  bool _deeperThan(double v, double ref) => _dip ? v < ref : v > ref;

  void _track(Map<String, double> values) {
    for (final e in values.entries) {
      final lo = _min[e.key], hi = _max[e.key];
      _min[e.key] = lo == null ? e.value : min(lo, e.value);
      _max[e.key] = hi == null ? e.value : max(hi, e.value);
    }
  }

  /// Feed one judged frame. Returns a RepResult when a rep completes.
  /// [leg]: lunges, the frame's front leg (FrameResult.frontLeg).
  RepResult? update(
    double main,
    Map<String, double> values,
    int tMs, {
    Side? leg,
  }) {
    if (stage == RepStage.ready) {
      if (jumpLimit != null) return _readyJump(main, values, tMs, leg);
      if (_started(main)) _start(main, values, tMs, leg);
      return null;
    }

    _track(values);

    if (jumpLimit != null) return _updateJump(main, values, tMs, leg);

    if (_returned(main)) return _complete(tMs);
    _followDepth(main, values, leg);
    return null;
  }

  void _start(double main, Map<String, double> values, int tMs, Side? leg) {
    stage = RepStage.goingDown;
    _startMs = tMs;
    _extreme = main;
    _atExtreme = Map.of(values);
    _legAtExtreme = leg;
    _min.clear();
    _max.clear();
    _track(values);
    _riseStartL = values['jump_rise_left'];
    _riseStartR = values['jump_rise_right'];
    _startHeel = values['heel_lift'];
  }

  /// A takeoff with no rep in progress: the rep starts at [startMs] (when the
  /// previous rep completed); its deepest value is the dip before this
  /// takeoff.
  void _startInAir(
    int startMs,
    double extreme,
    Map<String, double> atExtreme,
    double l0,
    double r0,
    double lower,
    Map<String, double> values,
  ) {
    stage = RepStage.comingUp;
    _startMs = startMs;
    _extreme = extreme;
    _atExtreme = Map.of(atExtreme);
    _legAtExtreme = null;
    _min.clear();
    _max.clear();
    _track(atExtreme);
    _track(values);
    _riseStartL = l0;
    _riseStartR = r0;
    _jumpHeight = lower;
    _airborne = true;
    _jumped = true;
    _startHeel = null; // no standing frame to measure the heel from
  }

  RepResult? _readyJump(
    double main,
    Map<String, double> values,
    int tMs,
    Side? leg,
  ) {
    final l = values['jump_rise_left'], r = values['jump_rise_right'];
    _readyMs ??= tMs;
    if (_readyExtreme == null || _deeperThan(main, _readyExtreme!)) {
      _readyExtreme = main;
      _readyAt = Map.of(values);
    }
    if (_returned(main)) _armed = true;
    final l0 = _readyL, r0 = _readyR;
    if (l != null && r != null && l0 != null && r0 != null && !_started(main)) {
      final lower = min(l - l0, r - r0);
      if (lower > jumpLimit!) {
        _startInAir(_readyMs!, _readyExtreme!, _readyAt, l0, r0, lower, values);
        return null;
      }
    }
    if (l != null) _readyL = l0 == null ? l : min(l0, l);
    if (r != null) _readyR = r0 == null ? r : min(r0, r);
    if (_armed && _started(main)) _start(main, values, tMs, leg);
    return null;
  }

  void _clearReady(
    int? tMs, {
    bool armed = true,
    double? extreme,
    Map<String, double> atExtreme = const {},
    double? lowL,
    double? lowR,
  }) {
    _armed = armed;
    _readyMs = tMs;
    _readyExtreme = extreme;
    _readyAt = Map.of(atExtreme);
    _readyL = lowL;
    _readyR = lowR;
  }

  void _followDepth(double main, Map<String, double> values, Side? leg) {
    if (_deeper(main)) {
      _extreme = main;
      _atExtreme = Map.of(values);
      _legAtExtreme = leg;
      stage = RepStage.goingDown;
    } else if (stage == RepStage.goingDown &&
        (main - _extreme!).abs() >= turnaround) {
      stage = RepStage.comingUp; // bottom passed
    }
  }

  RepResult? _updateJump(
    double main,
    Map<String, double> values,
    int tMs,
    Side? leg,
  ) {
    final limit = jumpLimit!;
    final l = values['jump_rise_left'], r = values['jump_rise_right'];
    if (!_jumped) {
      // Feet on the floor until the jump: each ankle's reference is its lowest
      // value so far in this rep, so a rep that starts mid-motion or a drifting
      // far ankle doesn't shrink the jump.
      if (l != null) {
        _riseStartL = _riseStartL == null ? l : min(_riseStartL!, l);
      }
      if (r != null) {
        _riseStartR = _riseStartR == null ? r : min(_riseStartR!, r);
      }
    }
    final l0 = _riseStartL, r0 = _riseStartR;
    if (l != null && r != null && l0 != null && r0 != null) {
      final lower = min(l - l0, r - r0); // both ankles must rise
      final extended = !_started(main); // a deep bend is never a takeoff
      if (extended && lower > _jumpHeight) _jumpHeight = lower;
      if (!_airborne && extended && lower > limit) {
        if (_landedMs != null) return _retakeoff(l, r, values, tMs);
        _airborne = true;
        _jumped = true;
      } else if (_airborne && lower <= limit) {
        _airborne = false; // landed: not both ankles up any more
        _landedMs = tMs;
        _landingMin = main;
        _landingAt = Map.of(values);
      }
    }

    if (_jumped) {
      final landed = _landedMs;
      if (landed == null) return null; // still in the air
      if (l != null) _lowL = _lowL == null ? l : min(_lowL!, l);
      if (r != null) _lowR = _lowR == null ? r : min(_lowR!, r);
      if (tMs - landed < landingWindowMs) {
        if (_deeperThan(main, _landingMin!)) {
          _landingMin = main;
          _landingAt = Map.of(values);
        }
        return null;
      }
      final lowMin = _landingMin, lowAt = _landingAt;
      final lowL = _lowL, lowR = _lowR;
      final result = _complete(tMs);
      // Still bent after the landing window: no new rep until the knee is back
      // up or the next takeoff.
      _clearReady(
        tMs,
        armed: _returned(main),
        extreme: lowMin,
        atExtreme: lowAt,
        lowL: lowL,
        lowR: lowR,
      );
      return result;
    }

    if (_returned(main)) {
      _backUpMs ??= tMs;
      if (tMs - _backUpMs! >= jumpWaitMs) return _complete(tMs);
      return null;
    }
    _backUpMs = null;
    _followDepth(main, values, leg);
    return null;
  }

  /// Takeoff inside the landing window (back-to-back jumps): this rep
  /// completes now, and the next one starts now, in the air, with the dip
  /// after the landing as its deepest value.
  RepResult? _retakeoff(
    double l,
    double r,
    Map<String, double> values,
    int tMs,
  ) {
    final dip = _landingMin!, dipAt = _landingAt;
    final l0 = _lowL ?? _riseStartL!, r0 = _lowR ?? _riseStartR!;
    final result = _complete(tMs);
    _startInAir(tMs, dip, dipAt, l0, r0, min(l - l0, r - r0), values);
    return result;
  }

  RepResult? _complete(int tMs) {
    final duration = tMs - _startMs;
    if (duration < minRepMs) {
      reset(keepCount: true); // formula v0.4.2: too short to be a real rep
      return null;
    }
    // Rep-level values for the form checks, readable with any "when" (bottom
    // or throughout): heel_rise (squat), jump_height and landing_knee_min
    // (jump squat).
    final startHeel = _startHeel, deepHeel = _atExtreme['heel_lift'];
    final repValues = <String, double>{
      if (startHeel != null && deepHeel != null)
        'heel_rise': deepHeel - startHeel,
      if (jumpLimit != null && _riseStartL != null && _riseStartR != null)
        'jump_height': _jumpHeight,
      if (jumpLimit != null && _landingMin != null)
        'landing_knee_min': _landingMin!,
    };
    count++;
    final result = RepResult(
      deepest: _extreme!,
      atDeepest: {..._atExtreme, ...repValues},
      durationMs: duration,
      endMs: tMs,
      minDuring: {..._min, ...repValues},
      maxDuring: {..._max, ...repValues},
      leg: _legAtExtreme,
    );
    reset(keepCount: true);
    return result;
  }

  /// Drop any rep in progress (after a pause or a new set).
  void reset({bool keepCount = false}) {
    stage = RepStage.ready;
    _extreme = null;
    _atExtreme = const {};
    _legAtExtreme = null;
    _min.clear();
    _max.clear();
    _startHeel = null;
    _riseStartL = null;
    _riseStartR = null;
    _jumpHeight = 0;
    _airborne = false;
    _jumped = false;
    _landedMs = null;
    _landingMin = null;
    _backUpMs = null;
    _landingAt = const {};
    _lowL = null;
    _lowR = null;
    _clearReady(null);
    if (!keepCount) count = 0;
  }
}
