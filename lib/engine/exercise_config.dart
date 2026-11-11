import 'landmarks.dart';

enum Posture { standing, floor }

/// dip: the main measurement goes down during a rep (squat knee angle).
/// hill: it goes up (glute bridge hip angle).
enum Direction { dip, hill }

/// What the engine needs to know about one exercise.
/// From Day 5, these values are loaded from assets/exercises/*.json.
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
  });

  final String id;
  final Posture posture;

  /// Joints that must pass the confidence check on the chosen side.
  final List<Joint> requiredJoints;

  /// Measurement names from the Measurement catalog.
  final List<String> measurements;

  final String mainMeasurement;
  final Direction direction;

  /// A rep starts when the main measurement passes this value.
  final double startThreshold;

  /// A rep completes when it comes back past this value.
  final double completeThreshold;
}

/// Temporary until the exercise file loader (Day 5).
/// Thresholds are the roadmap's starting values (Part 5); tune them with
/// the replay plots.
const squatConfig = ExerciseConfig(
  id: 'bodyweight_squat',
  posture: Posture.standing,
  requiredJoints: [Joint.shoulder, Joint.hip, Joint.knee, Joint.ankle],
  measurements: ['knee_angle', 'hip_angle', 'torso_lean', 'heel_lift'],
  mainMeasurement: 'knee_angle',
  direction: Direction.dip,
  startThreshold: 150,
  completeThreshold: 160,
);
