import 'landmarks.dart';

enum Posture { standing, floor }

/// dip: the main measurement goes down during a rep (squat knee angle).
/// hill: it goes up (glute bridge hip angle).
enum Direction { dip, hill }

/// What the engine needs to know about one exercise.
/// Loaded from assets/exercises/*.json (see lib/models/exercise_definition.dart).
class ExerciseConfig {
  const ExerciseConfig({
    required this.id,
    required this.posture,
    required this.requiredJoints,
    required this.measurements,
    required this.mainMeasurement,
    required this.direction,
    required this.startThreshold,
    required this.completeThreshold,
    this.bothSidesJoints = const [],
  });

  final String id;
  final Posture posture;

  /// Joints that must pass the confidence check on the chosen side.
  final List<Joint> requiredJoints;

  /// Joints that must pass on both sides (lunges: hip, knee and ankle).
  final List<Joint> bothSidesJoints;

  /// Measurement names from the Measurement catalog.
  final List<String> measurements;

  final String mainMeasurement;
  final Direction direction;

  /// A rep starts when the main measurement passes this value.
  final double startThreshold;

  /// A rep completes when it comes back past this value.
  final double completeThreshold;
}
