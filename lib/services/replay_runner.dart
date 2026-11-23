// Replay mode (roadmap Day 7). Owner: Member C.
// Runs replay frames through the engine in the same order as
// CameraTestScreen._handle: measurement layer, then rep counter (reset on an
// automatic pause), then the form judge on each completed rep.
// Plain Dart (no Flutter), so tests can use it.

import '../engine/form_judge.dart';
import '../engine/measurement_layer.dart';
import '../engine/rep_counter.dart';
import '../models/exercise_definition.dart';
import '../models/strictness.dart';
import 'replay_source.dart';

/// What happened on one frame.
class ReplayStep {
  const ReplayStep(this.input, this.frame, {this.rep, this.verdict});

  final ReplayFrame input;
  final FrameResult frame;

  /// Set only on the frame where a rep completed.
  final RepResult? rep;
  final RepVerdict? verdict;
}

class ReplayRunner {
  ReplayRunner(this.exercise, this.strictness)
    : layer = MeasurementLayer(exercise.config),
      counter = RepCounter.forExercise(exercise.config);

  final ExerciseDefinition exercise;
  final Strictness strictness;
  final MeasurementLayer layer;
  final RepCounter counter;

  /// Every completed rep so far, with its verdict.
  final List<(RepResult, RepVerdict)> reps = [];

  /// One frame through the engine. With [countReps] false (before the set
  /// begins), setup still runs but no reps are counted.
  ReplayStep step(ReplayFrame input, {bool countReps = true}) {
    final frame = layer.process(input.points, input.tMs);
    if (frame.status == FrameStatus.paused) {
      counter.reset(keepCount: true);
    }
    if (countReps && frame.status == FrameStatus.judged) {
      final main = frame.values[exercise.config.mainMeasurement];
      if (main != null) {
        final rep = counter.update(
          main,
          frame.values,
          input.tMs,
          leg: frame.frontLeg, // lunges: same as EngineWorkoutSource
        );
        if (rep != null) {
          final verdict = judgeRep(rep, exercise.formChecks, strictness);
          reps.add((rep, verdict));
          return ReplayStep(input, frame, rep: rep, verdict: verdict);
        }
      }
    }
    return ReplayStep(input, frame);
  }

  /// Runs a whole clip at once (tests).
  void runAll(Iterable<ReplayFrame> frames) {
    for (final f in frames) {
      step(f);
    }
  }

  /// Start the clip again from the beginning.
  void reset() {
    layer.reset();
    counter.reset();
    reps.clear();
  }
}
