// Rep counter (roadmap Part 5): one main measurement drives a state machine
// with two thresholds and a gap between them, so jitter is not a rep.
//
// Roadmap stages -> this code:
//   Ready      -> RepStage.ready
//   Going Down -> RepStage.goingDown
//   Bottom     -> the moment the value turns back by repTurnaroundDeg
//   Coming Up  -> RepStage.comingUp
//   Complete   -> the moment update() returns a RepResult

import 'constants.dart';
import 'exercise_config.dart';

enum RepStage { ready, goingDown, comingUp }

class RepResult {
  const RepResult({
    required this.deepest,
    required this.atDeepest,
    required this.durationMs,
    required this.endMs,
  });

  /// Deepest value of the main measurement (minimum for dip, maximum for hill).
  final double deepest;

  /// All smoothed measurements at the deepest frame (for the form judge).
  final Map<String, double> atDeepest;

  /// From leaving Ready to Complete.
  final int durationMs;
  final int endMs;
}

class RepCounter {
  RepCounter({
    required this.direction,
    required this.startThreshold,
    required this.completeThreshold,
    this.turnaround = repTurnaroundDeg,
  }) : assert(
         direction == Direction.dip
             ? completeThreshold > startThreshold
             : completeThreshold < startThreshold,
       );

  factory RepCounter.forExercise(ExerciseConfig c) => RepCounter(
    direction: c.direction,
    startThreshold: c.startThreshold,
    completeThreshold: c.completeThreshold,
  );

  final Direction direction;
  final double startThreshold;
  final double completeThreshold;
  final double turnaround;

  RepStage stage = RepStage.ready;
  int count = 0;
  double? _extreme;
  Map<String, double> _atExtreme = const {};
  int _startMs = 0;

  bool get _dip => direction == Direction.dip;
  bool _started(double v) => _dip ? v < startThreshold : v > startThreshold;
  bool _returned(double v) =>
      _dip ? v > completeThreshold : v < completeThreshold;
  bool _deeper(double v) => _dip ? v < _extreme! : v > _extreme!;

  /// Feed one judged frame. Returns a RepResult when a rep completes.
  RepResult? update(double main, Map<String, double> values, int tMs) {
    if (stage == RepStage.ready) {
      if (_started(main)) {
        stage = RepStage.goingDown;
        _startMs = tMs;
        _extreme = main;
        _atExtreme = Map.of(values);
      }
      return null;
    }

    if (_returned(main)) {
      count++;
      final result = RepResult(
        deepest: _extreme!,
        atDeepest: _atExtreme,
        durationMs: tMs - _startMs,
        endMs: tMs,
      );
      reset(keepCount: true);
      return result;
    }

    if (_deeper(main)) {
      _extreme = main;
      _atExtreme = Map.of(values);
      stage = RepStage.goingDown;
    } else if (stage == RepStage.goingDown &&
        (main - _extreme!).abs() >= turnaround) {
      stage = RepStage.comingUp; // bottom passed
    }
    return null;
  }

  /// Drop any rep in progress (after a pause or a new set).
  void reset({bool keepCount = false}) {
    stage = RepStage.ready;
    _extreme = null;
    _atExtreme = const {};
    if (!keepCount) count = 0;
  }
}
