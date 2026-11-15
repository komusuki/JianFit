import 'package:flutter/widgets.dart';

import '../models/workout_view.dart';

// Anything that can drive the setup check and live workout screens.
// Now: FakeWorkoutSource. Days 8 to 9: the engine (camera, ML Kit,
// measurement layer, rep counter, form judge). Swap the source, keep the screens.
abstract class WorkoutSource {
  /// Every new state, several times a second.
  Stream<WorkoutView> get updates;

  /// The latest state, for the first build.
  WorkoutView get current;

  /// Opens the camera and starts sending updates.
  Future<void> start();

  /// The camera picture, with the skeleton drawn on it if the source has one.
  Widget buildPreview();

  /// The countdown finished: start counting reps or hold time.
  void beginSet();

  /// The Pause and Resume buttons.
  void pause();
  void resume();

  /// Stops sending updates and releases the camera.
  Future<void> stop();
}
