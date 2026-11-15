// The squat's engine settings for tests. The app reads them from
// assets/exercises/bodyweight_squat.json; exercise_file_test.dart checks the
// two stay the same.

import 'package:jianfit/engine/exercise_config.dart';
import 'package:jianfit/engine/landmarks.dart';

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
