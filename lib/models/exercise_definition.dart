// One exercise definition file (roadmap Part 6), read from
// assets/exercises/<id>.json. The format is described in the Shared Formula
// Document, section "Exercise file format".
//
// This file is plain Dart (no Flutter), so `dart test` can check every
// exercise file. lib/services/exercise_loader.dart reads the files in the app.

import '../engine/exercise_config.dart';
import '../engine/landmarks.dart';
import '../engine/measurement_layer.dart';
import 'exercise_info.dart';
import 'strictness.dart';

/// range: one standard target for everyone. cleanliness: a limit per
/// strictness level. safety: one fixed limit.
enum CheckCategory { range, cleanliness, safety }

/// bottom: the value at the deepest frame of the rep.
/// throughout: the worst value during the whole rep.
enum CheckWhen { bottom, throughout }

/// max: the value must not go above the limit. min: not below it.
enum LimitKind { max, min }

class FormCheck {
  const FormCheck({
    required this.name,
    required this.category,
    required this.measurement,
    required this.timing,
    required this.kind,
    required this.limits,
    required this.cue,
    required this.priority,
  });

  final String name;
  final CheckCategory category;
  final String measurement;

  /// The file's "when" field.
  final CheckWhen timing;
  final LimitKind kind;

  /// The limit for each strictness level. Range and safety checks have the
  /// same value for all three.
  final Map<Strictness, double> limits;

  /// Short spoken correction, such as "Go lower."
  final String cue;

  /// 1 is the most important. Safety checks always come before the others.
  final int priority;

  double limitFor(Strictness s) => limits[s]!;
}

/// Everything one exercise file defines.
class ExerciseDefinition {
  const ExerciseDefinition({
    required this.info,
    required this.config,
    required this.formChecks,
    required this.orientation,
    required this.oneSided,
    this.demoClip,
  });

  /// What the screens show (Member B's model).
  final ExerciseInfo info;

  /// What the engine needs (measurement layer and rep counter).
  final ExerciseConfig config;

  final List<FormCheck> formChecks;

  /// portrait or landscape.
  final String orientation;

  /// Lunges: reps are counted per side (engine support comes on Day 9).
  final bool oneSided;

  final String? demoClip;

  String get id => info.id;

  /// Builds a definition from decoded JSON. [fileName] is the file's name,
  /// such as bodyweight_squat.json. Throws [ExerciseFileException] listing
  /// every problem found, so a file can be fixed in one go.
  factory ExerciseDefinition.fromJson(Object? json, String fileName) {
    final r = _Reader();
    if (json is! Map<String, dynamic>) {
      throw ExerciseFileException(fileName, ['the file must be a JSON object']);
    }

    // Basic
    final id = r.text(json, 'id');
    final expectedId = fileName.endsWith('.json')
        ? fileName.substring(0, fileName.length - 5)
        : fileName;
    if (id != null && id != expectedId) {
      r.add("id '$id' must match the file name ($expectedId)");
    }
    final name = r.text(json, 'name');
    final pattern = r.text(json, 'pattern');
    final level = r.text(json, 'level');
    final type = r.choice(json, 'type', ExerciseType.values);
    final demoClip = r.text(json, 'demo_clip', required: false);

    // Camera
    final camera = r.object(json, 'camera');
    String? view, orientation, placement;
    if (camera != null) {
      view = r.text(camera, 'view', path: 'camera');
      orientation = r.text(camera, 'orientation', path: 'camera');
      if (orientation != null &&
          orientation != 'portrait' &&
          orientation != 'landscape') {
        r.add(
          "camera.orientation must be portrait or landscape, not "
          "'$orientation'",
        );
      }
      placement = r.text(camera, 'placement', path: 'camera');
    }

    // Tracking
    final t = r.object(json, 'tracking');
    Posture? posture;
    List<Joint>? requiredJoints, bothSidesJoints;
    List<String>? measurements;
    String? mainMeasurement;
    Direction? direction;
    double? start, complete, jumpLimit;
    var bodyLineEnd = Joint.ankle;
    var oneSided = false;
    final isHold = type == ExerciseType.hold;
    if (t != null) {
      posture = r.choice(t, 'posture', Posture.values, path: 'tracking');
      requiredJoints = r.joints(t, 'required_joints', path: 'tracking');
      bothSidesJoints = r.joints(
        t,
        'both_sides_joints',
        path: 'tracking',
        required: false,
      );
      measurements = r.measurementNames(t, 'measurements', path: 'tracking');
      // Holds have no reps (Day 9): no main measurement, direction,
      // thresholds or jump.
      const repFields = [
        'main_measurement',
        'direction',
        'start_threshold',
        'complete_threshold',
        'jump_limit',
      ];
      if (isHold) {
        for (final f in repFields) {
          if (t.containsKey(f)) {
            r.add('tracking.$f is not used by hold exercises; remove it');
          }
        }
      }
      if (!isHold) {
        mainMeasurement = r.text(t, 'main_measurement', path: 'tracking');
      }
      if (mainMeasurement != null &&
          measurements != null &&
          !measurements.contains(mainMeasurement)) {
        r.add(
          "tracking.main_measurement '$mainMeasurement' must be one of "
          'tracking.measurements',
        );
      }
      if (!isHold) {
        direction = r.choice(
          t,
          'direction',
          Direction.values,
          path: 'tracking',
        );
        start = r.number(t, 'start_threshold', path: 'tracking');
        complete = r.number(t, 'complete_threshold', path: 'tracking');
      }
      // Jump squat (Day 9): needs both ankles' jump_rise.
      if (!isHold && t.containsKey('jump_limit')) {
        jumpLimit = r.number(t, 'jump_limit', path: 'tracking');
        if (jumpLimit != null && jumpLimit <= 0) {
          r.add('tracking.jump_limit must be more than 0');
        }
        if (measurements != null &&
            !(measurements.contains('jump_rise_left') &&
                measurements.contains('jump_rise_right'))) {
          r.add(
            'tracking.jump_limit needs jump_rise_left and jump_rise_right '
            'in tracking.measurements',
          );
        }
      }
      final end = r.text(t, 'body_line_end', path: 'tracking', required: false);
      if (end != null) {
        if (end == 'ankle' || end == 'knee') {
          bodyLineEnd = jointNames[end]!;
        } else {
          r.add("tracking.body_line_end must be ankle or knee, not '$end'");
        }
      }
      if (direction != null && start != null && complete != null) {
        if (direction == Direction.dip && complete <= start) {
          r.add(
            'dip: tracking.complete_threshold ($complete) must be above '
            'tracking.start_threshold ($start)',
          );
        }
        if (direction == Direction.hill && complete >= start) {
          r.add(
            'hill: tracking.complete_threshold ($complete) must be below '
            'tracking.start_threshold ($start)',
          );
        }
      }
      oneSided = r.flag(t, 'one_sided', path: 'tracking');
    }

    // Form checks
    final checks = <FormCheck>[];
    final rawChecks = json['form_checks'];
    if (rawChecks is! List) {
      r.add('form_checks is missing or is not a list');
    } else {
      final names = <String>{};
      for (var i = 0; i < rawChecks.length; i++) {
        final check = r.formCheck(rawChecks[i], 'form_checks[$i]', [
          ...?measurements,
          // Jump squat: values the rep counter adds to each rep.
          if (jumpLimit != null) ...repMeasurements,
        ]);
        if (check == null) continue;
        if (!names.add(check.name)) {
          r.add("form_checks[$i]: the name '${check.name}' is used twice");
        }
        checks.add(check);
      }
    }

    if (r.problems.isNotEmpty) {
      throw ExerciseFileException(fileName, r.problems);
    }
    final exerciseId = id!;
    return ExerciseDefinition(
      info: ExerciseInfo(
        id: exerciseId,
        name: name!,
        pattern: pattern!,
        level: level!,
        type: type!,
        cameraView: view!,
        placement: placement!,
      ),
      config: ExerciseConfig(
        id: exerciseId,
        posture: posture!,
        requiredJoints: requiredJoints!,
        bothSidesJoints: bothSidesJoints ?? const [],
        measurements: measurements!,
        mainMeasurement: mainMeasurement,
        direction: direction,
        startThreshold: start,
        completeThreshold: complete,
        jumpLimit: jumpLimit,
        bodyLineEnd: bodyLineEnd,
      ),
      formChecks: checks,
      orientation: orientation!,
      oneSided: oneSided,
      demoClip: demoClip,
    );
  }
}

/// A file that doesn't follow the format. [problems] lists every mistake.
class ExerciseFileException implements Exception {
  ExerciseFileException(this.fileName, this.problems);
  final String fileName;
  final List<String> problems;

  @override
  String toString() =>
      '$fileName has ${problems.length} problem(s):\n'
      '${problems.map((p) => '  - $p').join('\n')}';
}

/// Values the rep counter adds to each jump squat rep, usable in form checks
/// when tracking.jump_limit is set.
const List<String> repMeasurements = ['jump_height', 'landing_knee_min'];

/// JSON joint names -> engine joints.
const Map<String, Joint> jointNames = {
  'ear': Joint.ear,
  'shoulder': Joint.shoulder,
  'elbow': Joint.elbow,
  'wrist': Joint.wrist,
  'hip': Joint.hip,
  'knee': Joint.knee,
  'ankle': Joint.ankle,
  'heel': Joint.heel,
  'foot_index': Joint.footIndex,
};

/// Reads fields and collects problems instead of stopping at the first.
class _Reader {
  final List<String> problems = [];

  void add(String problem) => problems.add(problem);

  String _key(String? path, String key) => path == null ? key : '$path.$key';

  Map<String, dynamic>? object(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is Map<String, dynamic>) return v;
    add('$key is missing or is not an object');
    return null;
  }

  String? text(
    Map<String, dynamic> m,
    String key, {
    String? path,
    bool required = true,
  }) {
    final v = m[key];
    if (v == null) {
      if (required) add('${_key(path, key)} is missing');
      return null;
    }
    if (v is! String || v.trim().isEmpty) {
      add('${_key(path, key)} must be non-empty text');
      return null;
    }
    return v;
  }

  double? number(Map<String, dynamic> m, String key, {String? path}) {
    final v = m[key];
    if (v is num) return v.toDouble();
    add('${_key(path, key)} is missing or is not a number');
    return null;
  }

  bool flag(Map<String, dynamic> m, String key, {String? path}) {
    final v = m[key];
    if (v == null) return false;
    if (v is bool) return v;
    add('${_key(path, key)} must be true or false');
    return false;
  }

  T? choice<T extends Enum>(
    Map<String, dynamic> m,
    String key,
    List<T> values, {
    String? path,
  }) {
    final v = m[key];
    for (final e in values) {
      if (e.name == v) return e;
    }
    add(
      "${_key(path, key)} must be one of "
      "${values.map((e) => e.name).join(', ')}, not '$v'",
    );
    return null;
  }

  List<Joint>? joints(
    Map<String, dynamic> m,
    String key, {
    String? path,
    bool required = true,
  }) {
    final v = m[key];
    if (v == null && !required) return const [];
    if (v is! List || (required && v.isEmpty)) {
      add('${_key(path, key)} must be a non-empty list of joint names');
      return null;
    }
    final out = <Joint>[];
    for (final name in v) {
      final j = jointNames[name];
      if (j == null) {
        add(
          "${_key(path, key)}: unknown joint '$name' "
          "(use ${jointNames.keys.join(', ')})",
        );
      } else {
        out.add(j);
      }
    }
    return out;
  }

  List<String>? measurementNames(
    Map<String, dynamic> m,
    String key, {
    String? path,
  }) {
    final v = m[key];
    if (v is! List || v.isEmpty) {
      add('${_key(path, key)} must be a non-empty list of measurement names');
      return null;
    }
    final out = <String>[];
    for (final name in v) {
      if (name is String && measurementRegistry.containsKey(name)) {
        out.add(name);
      } else {
        add(
          "${_key(path, key)}: unknown measurement '$name' "
          '(the engine knows ${measurementRegistry.keys.join(', ')})',
        );
      }
    }
    return out;
  }

  FormCheck? formCheck(Object? raw, String path, List<String> measurements) {
    if (raw is! Map<String, dynamic>) {
      add('$path must be an object');
      return null;
    }
    final before = problems.length;
    final name = text(raw, 'name', path: path);
    final category = choice(raw, 'category', CheckCategory.values, path: path);
    final measurement = text(raw, 'measurement', path: path);
    if (measurement != null && !measurements.contains(measurement)) {
      add(
        "$path.measurement '$measurement' must be one of "
        'tracking.measurements',
      );
    }
    final timing = raw['when'] == null
        ? CheckWhen.bottom
        : choice(raw, 'when', CheckWhen.values, path: path);
    final cue = text(raw, 'cue', path: path);
    final priority = raw['priority'];
    if (priority is! int || priority < 1) {
      add('$path.priority must be a whole number of 1 or more');
    }

    final hasMax = raw.containsKey('max'), hasMin = raw.containsKey('min');
    LimitKind? kind;
    Map<Strictness, double>? limits;
    if (hasMax == hasMin) {
      add('$path needs exactly one of max or min');
    } else {
      kind = hasMax ? LimitKind.max : LimitKind.min;
      final limit = raw[kind.name];
      if (category == CheckCategory.cleanliness) {
        limits = _strictnessLimits(limit, '$path.${kind.name}');
      } else if (category != null) {
        if (limit is num) {
          limits = {for (final s in Strictness.values) s: limit.toDouble()};
        } else {
          add(
            '$path.${kind.name} must be one number for a '
            '${category.name} check',
          );
        }
      }
    }

    if (problems.length != before) return null;
    return FormCheck(
      name: name!,
      category: category!,
      measurement: measurement!,
      timing: timing!,
      kind: kind!,
      limits: limits!,
      cue: cue!,
      priority: priority as int,
    );
  }

  Map<Strictness, double>? _strictnessLimits(Object? v, String path) {
    final names = Strictness.values.map((s) => s.name).join(', ');
    if (v is! Map<String, dynamic>) {
      add('$path must be an object with $names for a cleanliness check');
      return null;
    }
    final out = <Strictness, double>{};
    for (final s in Strictness.values) {
      final x = v[s.name];
      if (x is num) {
        out[s] = x.toDouble();
      } else {
        add('$path.${s.name} is missing or is not a number');
      }
    }
    for (final k in v.keys) {
      if (!Strictness.values.any((s) => s.name == k)) {
        add("$path: unknown strictness level '$k' (use $names)");
      }
    }
    return out.length == Strictness.values.length ? out : null;
  }
}
