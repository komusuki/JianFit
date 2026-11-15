// Everything the setup check and live workout screens show, in one place.
// A WorkoutSource fills it in: fake data now, Member A's engine on Days 8 to 9.
// The screens only read it, so swapping the source needs no screen changes.

class WorkoutView {
  const WorkoutView({
    this.personVisible = false,
    this.ready = false,
    this.paused = false,
    this.correct = 0,
    this.attempted = 0,
    this.cue,
    this.holdSeconds = 0,
    this.lastRepCorrect,
  });

  /// A person is in the frame (engine: MeasurementLayer.hasPerson).
  final bool personVisible;

  /// Setup is done, so judging can start (engine: MeasurementLayer.isReady).
  final bool ready;

  /// Paused by the user, or no usable frames for 2 seconds (FrameStatus.paused).
  final bool paused;

  /// Reps that passed every form check (engine: RepVerdict.correct).
  final int correct;

  /// All finished reps, correct or not.
  final int attempted;

  /// The correction to show and speak (engine: RepVerdict.topFailed.cue).
  final String? cue;

  /// Seconds held so far, for hold exercises such as the plank.
  final double holdSeconds;

  /// The latest rep's result, for green or red joints. Null before the first rep.
  final bool? lastRepCorrect;
}
