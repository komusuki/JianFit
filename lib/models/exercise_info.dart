// What the screens show about one exercise (roadmap Part 6: Basic and Camera).
// The engine's settings for the same exercise are in
// lib/engine/exercise_config.dart and use the same id.
// Fake data until Member A's exercise file loader (Day 5).

enum ExerciseType { reps, hold }

class ExerciseInfo {
  const ExerciseInfo({
    required this.id,
    required this.name,
    required this.pattern,
    required this.level,
    required this.type,
    required this.cameraView,
    required this.placement,
  });

  final String id;
  final String name;
  final String pattern;
  final String level;
  final ExerciseType type;
  final String cameraView;
  final String placement;
}

const _standing = 'Phone at hip height, 2 to 3 meters away, facing your side.';
const _floor = 'Phone near floor level, 2 to 3 meters away, facing your side.';

const fakeExercises = [
  ExerciseInfo(id: 'bodyweight_squat', name: 'Bodyweight squat', pattern: 'Squat', level: 'Beginner', type: ExerciseType.reps, cameraView: 'Side', placement: _standing),
  ExerciseInfo(id: 'jump_squat', name: 'Jump squat', pattern: 'Squat', level: 'Intermediate', type: ExerciseType.reps, cameraView: 'Side', placement: _standing),
  ExerciseInfo(id: 'knee_push_up', name: 'Knee push-up', pattern: 'Push-up', level: 'Beginner', type: ExerciseType.reps, cameraView: 'Side', placement: _floor),
  ExerciseInfo(id: 'standard_push_up', name: 'Standard push-up', pattern: 'Push-up', level: 'Intermediate', type: ExerciseType.reps, cameraView: 'Side', placement: _floor),
  ExerciseInfo(id: 'forward_lunge', name: 'Forward lunge', pattern: 'Lunge', level: 'Beginner', type: ExerciseType.reps, cameraView: 'Side', placement: _standing),
  ExerciseInfo(id: 'reverse_lunge', name: 'Reverse lunge', pattern: 'Lunge', level: 'Beginner', type: ExerciseType.reps, cameraView: 'Side', placement: _standing),
  ExerciseInfo(id: 'forearm_plank', name: 'Forearm plank', pattern: 'Plank', level: 'Beginner', type: ExerciseType.hold, cameraView: 'Side', placement: _floor),
  ExerciseInfo(id: 'glute_bridge', name: 'Glute bridge', pattern: 'Bridge', level: 'Beginner', type: ExerciseType.reps, cameraView: 'Side', placement: _floor),
];