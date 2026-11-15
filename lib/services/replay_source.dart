// Replay mode (roadmap Day 7). Owner: Member C.
// Reads a pose CSV written by tools/extract_pose.py:
//   frame, t_ms, width, height, lm0_x, lm0_y, lm0_c ... lm32_c
// in pixels of the upright image, one row per processed frame. A row with no
// person has empty landmark cells. Plain Dart (no Flutter), so tests can use it.

import '../engine/geometry.dart';

/// One row of a replay CSV: the same input the camera gives the engine.
class ReplayFrame {
  const ReplayFrame({
    required this.frame,
    required this.tMs,
    required this.width,
    required this.height,
    required this.points,
  });

  /// Frame number in the original video.
  final int frame;

  /// Time in the video, in milliseconds (the engine's tMs).
  final int tMs;

  /// Video size in pixels, for drawing.
  final double width;
  final double height;

  /// Landmark index (0 to 32) -> point. Empty when no person was found,
  /// which the engine treats as "no person", like PoseService.toPoints(null).
  final Map<int, Pt> points;
}

/// Parses the text of a replay CSV. Throws FormatException on a bad header.
List<ReplayFrame> parseReplayCsv(String text) {
  final lines = text
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) throw const FormatException('The replay CSV is empty.');
  final header = lines.first.split(',').map((h) => h.trim()).toList();
  int col(String name) {
    final i = header.indexOf(name);
    if (i < 0) {
      throw FormatException(
        'Column $name is missing. Make the CSV with tools/extract_pose.py.',
      );
    }
    return i;
  }

  final iFrame = col('frame'), iT = col('t_ms');
  final iW = col('width'), iH = col('height');
  final lm = [
    for (var k = 0; k < 33; k++) (col('lm${k}_x'), col('lm${k}_y'), col('lm${k}_c')),
  ];

  final frames = <ReplayFrame>[];
  for (final line in lines.skip(1)) {
    final cells = line.split(',');
    if (cells.length < header.length) continue; // cut-off last line
    final points = <int, Pt>{};
    if (cells[lm[0].$1].trim().isNotEmpty) {
      for (var k = 0; k < 33; k++) {
        final (ix, iy, ic) = lm[k];
        points[k] = Pt(
          double.parse(cells[ix]),
          double.parse(cells[iy]),
          double.tryParse(cells[ic]) ?? 0,
        );
      }
    }
    frames.add(
      ReplayFrame(
        frame: int.parse(cells[iFrame]),
        tMs: double.parse(cells[iT]).round(),
        width: double.parse(cells[iW]),
        height: double.parse(cells[iH]),
        points: points,
      ),
    );
  }
  return frames;
}

/// The exercise id from a replay file name, using the video naming rule:
/// 'assets/replays/reverse-lunge_S01_side_correct_01.csv' -> 'reverse_lunge'.
/// Same as exercise_id() in tools/measurements.py.
String exerciseIdFromReplayName(String path) {
  final name = path.split('/').last.split('\\').last;
  return name.split('_').first.toLowerCase().replaceAll('-', '_');
}
