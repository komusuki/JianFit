import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/form_judge.dart';
import '../engine/geometry.dart';
import '../engine/measurement_layer.dart';
import '../models/exercise_info.dart';
import '../models/strictness.dart';
import '../models/workout_view.dart';
import 'exercise_loader.dart';
import 'replay_runner.dart';
import 'replay_source.dart';
import 'workout_source.dart';

// Replay mode (roadmap Day 7). Owner: Member C.
// Drives the setup check and live workout screens from a recorded pose CSV in
// assets/replays/ instead of the camera, through the real engine
// (measurement layer, rep counter, form judge). Turn it on with the developer
// switch in Settings.
//
// The clip is the first file in assets/replays/ for this exercise, by name:
// reverse-lunge_S01_side_correct_01.csv is a reverse_lunge clip.
// A recording has no countdown, so playback waits on the frame where setup
// finished until beginSet(), like a person holding still for the 3-2-1.
// Hold exercises (plank) are not timed yet: the engine's hold timer comes on Day 9.
class ReplayWorkoutSource implements WorkoutSource {
  ReplayWorkoutSource(this.exercise, {required this.strictness});

  static const folder = 'assets/replays/';

  final ExerciseInfo exercise;
  final Strictness strictness;
  final _updates = StreamController<WorkoutView>.broadcast();
  WorkoutView _current = const WorkoutView();

  ReplayRunner? _runner;
  List<ReplayFrame> _frames = const [];
  ReplayFrame? _shown;
  String? _message = 'Loading replay...';
  Timer? _timer;
  final _clock = Stopwatch();
  int _startMs = 0;
  int _index = 0;

  bool _counting = false;
  bool _manualPause = false;
  bool _autoPaused = false;
  bool _waitingForCountdown = false;
  bool _stopped = false;
  int _correct = 0;
  int _attempted = 0;
  String? _cue;
  bool? _lastRepCorrect;

  @override
  Stream<WorkoutView> get updates => _updates.stream;

  @override
  WorkoutView get current => _current;

  @override
  Future<void> start() async {
    final loaded = await ExerciseLoader.loadAll();
    final definition = loaded.exercises[exercise.id];
    if (definition == null) {
      _fail('No exercise file assets/exercises/${exercise.id}.json yet.');
      return;
    }
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final clips =
        manifest
            .listAssets()
            .where(
              (a) =>
                  a.startsWith(folder) &&
                  a.endsWith('.csv') &&
                  exerciseIdFromReplayName(a) == exercise.id,
            )
            .toList()
          ..sort();
    if (clips.isEmpty) {
      _fail('No ${exercise.id} clip in $folder.');
      return;
    }
    try {
      _frames = parseReplayCsv(await rootBundle.loadString(clips.first));
    } on FormatException catch (e) {
      _fail(e.message);
      return;
    }
    if (_stopped || _frames.isEmpty) return;
    _runner = ReplayRunner(definition, strictness);
    _message = null;
    _startMs = _frames.first.tMs;
    debugPrint(
      'REPLAY ${clips.first}: ${_frames.length} frames, '
      'strictness ${strictness.name}',
    );
    _clock.start();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
  }

  void _fail(String message) {
    debugPrint('REPLAY: $message');
    _message = message;
    _publish();
  }

  /// Feed every frame whose time has come, then publish the new state.
  void _tick() {
    final runner = _runner;
    if (runner == null || _stopped) return;
    var changed = false;
    while (_index < _frames.length &&
        _frames[_index].tMs - _startMs <= _clock.elapsedMilliseconds) {
      final f = _frames[_index++];
      final s = runner.step(f, countReps: _counting);
      _shown = f;
      changed = true;
      if (s.frame.status == FrameStatus.paused) {
        _autoPaused = true;
        debugPrint('REPLAY paused at ${(f.tMs / 1000).toStringAsFixed(2)} s');
      } else if (s.frame.status == FrameStatus.judged) {
        _autoPaused = false;
      }
      final rep = s.rep, verdict = s.verdict;
      if (rep != null && verdict != null) {
        _attempted++;
        if (verdict.correct) _correct++;
        _lastRepCorrect = verdict.correct;
        _cue = verdict.topFailed?.cue;
        debugPrint(
          'REP $_attempted: '
          '${((rep.endMs - rep.durationMs) / 1000).toStringAsFixed(2)} to '
          '${(rep.endMs / 1000).toStringAsFixed(2)} s, '
          'deepest=${rep.deepest.toStringAsFixed(1)}  '
          '${verdict.correct ? 'correct' : 'attempted (${_names(verdict)})'}',
        );
      }
      // Setup just finished: wait here until the countdown ends.
      if (!_counting && runner.layer.isReady) {
        _waitingForCountdown = true;
        _clock.stop();
        break;
      }
    }
    if (_index >= _frames.length && _clock.isRunning) {
      _clock.stop();
      debugPrint('REPLAY finished: $_correct correct of $_attempted attempted');
    }
    if (changed) _publish();
  }

  static String _names(RepVerdict v) => v.failed.map((c) => c.name).join(', ');

  void _publish() {
    if (_stopped) return;
    final runner = _runner;
    final points = _shown?.points ?? const <int, Pt>{};
    _current = WorkoutView(
      personVisible: runner != null && runner.layer.hasPerson(points),
      ready: runner != null && runner.layer.isReady,
      paused: _manualPause || _autoPaused,
      correct: _correct,
      attempted: _attempted,
      cue: _cue,
      lastRepCorrect: _lastRepCorrect,
    );
    _updates.add(_current);
  }

  @override
  Widget buildPreview() {
    final f = _shown;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (f != null) CustomPaint(painter: ReplayPointsPainter(f)),
          Positioned(
            left: 8,
            bottom: 8,
            child: Text(
              _message ?? 'REPLAY  ${((f?.tMs ?? 0) / 1000).toStringAsFixed(1)} s',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void beginSet() {
    _counting = true;
    if (_waitingForCountdown) {
      _waitingForCountdown = false;
      if (!_manualPause) _clock.start();
    }
  }

  @override
  void pause() {
    _manualPause = true;
    _clock.stop();
    _publish();
  }

  @override
  void resume() {
    _manualPause = false;
    if (!_waitingForCountdown && _index < _frames.length) _clock.start();
    _publish();
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    _clock.stop();
    await _updates.close();
  }
}

/// Draws the body points of one replay frame, fitted to the screen.
class ReplayPointsPainter extends CustomPainter {
  ReplayPointsPainter(this.frame);

  final ReplayFrame frame;

  static const _bones = [
    (7, 11), (8, 12), (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27), (24, 26), (26, 28),
    (27, 29), (29, 31), (27, 31), (28, 30), (30, 32), (28, 32),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final pts = frame.points;
    if (pts.isEmpty || frame.width <= 0 || frame.height <= 0) return;
    final sx = size.width / frame.width, sy = size.height / frame.height;
    final scale = sx < sy ? sx : sy;
    final dx = (size.width - frame.width * scale) / 2;
    final dy = (size.height - frame.height * scale) / 2;
    Offset at(Pt p) => Offset(dx + p.x * scale, dy + p.y * scale);
    bool seen(int i) => (pts[i]?.c ?? 0) >= 0.5;

    final bone = Paint()
      ..color = Colors.tealAccent
      ..strokeWidth = 3;
    for (final (a, b) in _bones) {
      if (seen(a) && seen(b)) canvas.drawLine(at(pts[a]!), at(pts[b]!), bone);
    }
    final dot = Paint()..color = Colors.white;
    for (final p in pts.values) {
      if (p.c >= 0.5) canvas.drawCircle(at(p), 4, dot);
    }
  }

  @override
  bool shouldRepaint(ReplayPointsPainter old) => old.frame != frame;
}
