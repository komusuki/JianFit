// Loads every exercise definition file in assets/exercises/ (roadmap Part 6:
// new exercises need no code changes). Bad files are skipped and reported,
// so one typo doesn't stop the app.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/exercise_definition.dart';

class ExerciseLoadResult {
  const ExerciseLoadResult(this.exercises, this.errors);

  /// Good files, by id.
  final Map<String, ExerciseDefinition> exercises;

  /// One line per problem, starting with the file name.
  final List<String> errors;
}

class ExerciseLoader {
  static const folder = 'assets/exercises/';

  /// Reads every .json file in [folder]. Flutter can't list an asset folder
  /// directly, so the asset manifest gives the file names.
  static Future<ExerciseLoadResult> loadAll({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(b);
    final paths =
        manifest
            .listAssets()
            .where((p) => p.startsWith(folder) && p.endsWith('.json'))
            .toList()
          ..sort();

    final exercises = <String, ExerciseDefinition>{};
    final errors = <String>[];
    for (final path in paths) {
      final fileName = path.substring(folder.length);
      try {
        final json = jsonDecode(await b.loadString(path));
        final def = ExerciseDefinition.fromJson(json, fileName);
        if (exercises.containsKey(def.id)) {
          errors.add("$fileName: the id '${def.id}' is used by another file");
          continue;
        }
        exercises[def.id] = def;
      } on ExerciseFileException catch (e) {
        errors.addAll(e.problems.map((p) => '$fileName: $p'));
      } on FormatException catch (e) {
        errors.add('$fileName: not valid JSON (${e.message})');
      }
    }
    for (final e in errors) {
      debugPrint('EXERCISE FILE ERROR $e');
    }
    return ExerciseLoadResult(exercises, errors);
  }
}
