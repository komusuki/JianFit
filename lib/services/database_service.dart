// Local SQLite database (roadmap Part 12). Owner: Member C.
//
// Tables: routines, routine_items, sessions, sets, reps, failed_checks.
// Settings stay in shared_preferences (Member B), not here.
// Times are stored as milliseconds since epoch.

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/workout_records.dart';

class DatabaseService {
  /// [path] and [factory] are for tests (an in-memory database through
  /// sqflite_common_ffi). The app uses the defaults.
  DatabaseService({this.path, DatabaseFactory? factory})
    : _factory = factory ?? databaseFactory;

  static const fileName = 'jianfit.db';
  static const schemaVersion = 1;

  final String? path;
  final DatabaseFactory _factory;
  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final file = path ?? p.join(await _factory.getDatabasesPath(), fileName);
    return _factory.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _createTables(db),
      ),
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> _createTables(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE routines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE routine_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        routine_id INTEGER NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        exercise_id TEXT NOT NULL,
        target_reps INTEGER,
        target_seconds INTEGER,
        sets INTEGER NOT NULL,
        rest_sec INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        mode TEXT NOT NULL,
        routine_id INTEGER REFERENCES routines(id) ON DELETE SET NULL,
        strictness TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        exercise_id TEXT NOT NULL,
        set_number INTEGER NOT NULL,
        target_reps INTEGER,
        target_seconds INTEGER,
        correct_reps INTEGER NOT NULL,
        attempted_reps INTEGER NOT NULL,
        hold_seconds REAL
      )''');
    batch.execute('''
      CREATE TABLE reps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        set_id INTEGER NOT NULL REFERENCES sets(id) ON DELETE CASCADE,
        rep_number INTEGER NOT NULL,
        correct INTEGER NOT NULL,
        depth REAL,
        duration_ms INTEGER NOT NULL,
        ended_at_ms INTEGER,
        front_leg TEXT
      )''');
    batch.execute('''
      CREATE TABLE failed_checks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rep_id INTEGER NOT NULL REFERENCES reps(id) ON DELETE CASCADE,
        check_name TEXT NOT NULL,
        category TEXT,
        value REAL
      )''');
    batch.execute('CREATE INDEX idx_sets_session ON sets(session_id)');
    batch.execute('CREATE INDEX idx_reps_set ON reps(set_id)');
    batch.execute('CREATE INDEX idx_checks_rep ON failed_checks(rep_id)');
    batch.execute('CREATE INDEX idx_sessions_started ON sessions(started_at)');
    await batch.commit(noResult: true);
  }

  // ---- Sessions ----

  /// Saves a whole session (sets, reps and failed checks) in one transaction.
  /// Returns the new session id.
  Future<int> saveSession(SessionRecord s) async {
    final db = await database;
    return db.transaction((txn) async {
      final sessionId = await txn.insert('sessions', {
        'started_at': s.startedAt.millisecondsSinceEpoch,
        'ended_at': s.endedAt?.millisecondsSinceEpoch,
        'mode': s.mode,
        'routine_id': s.routineId,
        'strictness': s.strictness,
      });
      for (final set in s.sets) {
        final setId = await txn.insert('sets', {
          'session_id': sessionId,
          'exercise_id': set.exerciseId,
          'set_number': set.setNumber,
          'target_reps': set.targetReps,
          'target_seconds': set.targetSeconds,
          'correct_reps': set.correctReps,
          'attempted_reps': set.attemptedReps,
          'hold_seconds': set.holdSeconds,
        });
        for (final rep in set.reps) {
          final repId = await txn.insert('reps', {
            'set_id': setId,
            'rep_number': rep.repNumber,
            'correct': rep.correct ? 1 : 0,
            'depth': rep.depth,
            'duration_ms': rep.durationMs,
            'ended_at_ms': rep.endedAtMs,
            'front_leg': rep.frontLeg,
          });
          for (final c in rep.failedChecks) {
            await txn.insert('failed_checks', {
              'rep_id': repId,
              'check_name': c.name,
              'category': c.category,
              'value': c.value,
            });
          }
        }
      }
      return sessionId;
    });
  }

  /// History list: every session, newest first, with its rep totals.
  Future<List<SessionListItem>> listSessions() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.id, s.started_at, s.ended_at, s.mode, s.strictness,
             COALESCE(SUM(t.correct_reps), 0) AS correct,
             COALESCE(SUM(t.attempted_reps), 0) AS attempted,
             GROUP_CONCAT(DISTINCT t.exercise_id) AS exercises
      FROM sessions s
      LEFT JOIN sets t ON t.session_id = s.id
      GROUP BY s.id
      ORDER BY s.started_at DESC, s.id DESC''');
    return [
      for (final r in rows)
        SessionListItem(
          id: r['id'] as int,
          startedAt: _time(r['started_at'])!,
          endedAt: _time(r['ended_at']),
          mode: r['mode'] as String,
          strictness: r['strictness'] as String,
          correctReps: r['correct'] as int,
          attemptedReps: r['attempted'] as int,
          exerciseIds: (r['exercises'] as String?)?.split(',') ?? const [],
        ),
    ];
  }

  /// Summary of one session, or null if the id does not exist.
  Future<SessionSummary?> getSummary(int sessionId) async {
    final db = await database;
    final found = await db.query(
      'sessions',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    if (found.isEmpty) return null;

    final setRows = await db.query(
      'sets',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id',
    );
    final sets = [
      for (final r in setRows)
        SetSummary(
          exerciseId: r['exercise_id'] as String,
          setNumber: r['set_number'] as int,
          correctReps: r['correct_reps'] as int,
          attemptedReps: r['attempted_reps'] as int,
          targetReps: r['target_reps'] as int?,
          targetSeconds: r['target_seconds'] as int?,
          holdSeconds: (r['hold_seconds'] as num?)?.toDouble(),
        ),
    ];

    final top = await db.rawQuery(
      '''
      SELECT f.check_name AS name, COUNT(*) AS n
      FROM failed_checks f
      JOIN reps r ON f.rep_id = r.id
      JOIN sets t ON r.set_id = t.id
      WHERE t.session_id = ?
      GROUP BY f.check_name
      ORDER BY n DESC, f.check_name ASC
      LIMIT 1''',
      [sessionId],
    );

    return SessionSummary(
      sessionId: sessionId,
      correctReps: sets.fold(0, (sum, s) => sum + s.correctReps),
      attemptedReps: sets.fold(0, (sum, s) => sum + s.attemptedReps),
      topMistake: top.isEmpty ? null : top.first['name'] as String,
      topMistakeCount: top.isEmpty ? 0 : top.first['n'] as int,
      sets: sets,
    );
  }

  /// Deletes a session and everything in it.
  Future<void> deleteSession(int sessionId) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  // ---- Routines ----

  /// Saves a new routine with its items. Returns the routine id.
  Future<int> saveRoutine(Routine routine) async {
    final db = await database;
    return db.transaction((txn) async {
      final id = await txn.insert('routines', {
        'name': routine.name,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      for (var i = 0; i < routine.items.length; i++) {
        final item = routine.items[i];
        await txn.insert('routine_items', {
          'routine_id': id,
          'position': i,
          'exercise_id': item.exerciseId,
          'target_reps': item.targetReps,
          'target_seconds': item.targetSeconds,
          'sets': item.sets,
          'rest_sec': item.restSec,
        });
      }
      return id;
    });
  }

  /// Every routine with its items in order, newest routine first.
  Future<List<Routine>> listRoutines() async {
    final db = await database;
    final routines = await db.query('routines', orderBy: 'created_at DESC, id DESC');
    final result = <Routine>[];
    for (final r in routines) {
      final items = await db.query(
        'routine_items',
        where: 'routine_id = ?',
        whereArgs: [r['id']],
        orderBy: 'position',
      );
      result.add(
        Routine(
          id: r['id'] as int,
          name: r['name'] as String,
          items: [
            for (final i in items)
              RoutineItem(
                exerciseId: i['exercise_id'] as String,
                targetReps: i['target_reps'] as int?,
                targetSeconds: i['target_seconds'] as int?,
                sets: i['sets'] as int,
                restSec: i['rest_sec'] as int,
              ),
          ],
        ),
      );
    }
    return result;
  }

  Future<void> deleteRoutine(int routineId) async {
    final db = await database;
    await db.delete('routines', where: 'id = ?', whereArgs: [routineId]);
  }

  // ---- Fake data (development only) ----

  /// Adds one routine and three past sessions so the History and Summary
  /// screens have something to show. Does nothing if any session exists.
  /// Returns true if it added data.
  Future<bool> seedFakeData({DateTime? now}) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sessions'),
    );
    if ((count ?? 0) > 0) return false;

    final today = now ?? DateTime.now();
    final legDay = await saveRoutine(
      const Routine(
        name: 'Leg day (fake)',
        items: [
          RoutineItem(exerciseId: 'forward_lunge', targetReps: 8, sets: 1, restSec: 60),
          RoutineItem(exerciseId: 'reverse_lunge', targetReps: 8, sets: 1, restSec: 60),
          RoutineItem(exerciseId: 'forearm_plank', targetSeconds: 30, sets: 1, restSec: 60),
        ],
      ),
    );

    await saveSession(
      SessionRecord(
        startedAt: today.subtract(const Duration(days: 3, hours: 2)),
        endedAt: today.subtract(const Duration(days: 3, hours: 1, minutes: 50)),
        mode: 'single',
        strictness: 'standard',
        sets: [
          _fakeSet('bodyweight_squat', 1, 10, {4: ['heel_lift']}),
          _fakeSet('bodyweight_squat', 2, 10, {6: ['heel_lift'], 8: ['torso_lean'], 9: ['heel_lift']}),
        ],
      ),
    );
    await saveSession(
      SessionRecord(
        startedAt: today.subtract(const Duration(days: 2, hours: 3)),
        endedAt: today.subtract(const Duration(days: 2, hours: 2, minutes: 45)),
        mode: 'custom',
        routineId: legDay,
        strictness: 'standard',
        sets: [
          _fakeSet('forward_lunge', 1, 8, {3: ['torso_lean'], 7: ['shallow_front_knee', 'back_knee_high']}),
          _fakeSet('reverse_lunge', 1, 8, const {}),
          const SetRecord(exerciseId: 'forearm_plank', setNumber: 1, targetSeconds: 30, holdSeconds: 27.5),
        ],
      ),
    );
    await saveSession(
      SessionRecord(
        startedAt: today.subtract(const Duration(days: 1, hours: 1)),
        endedAt: today.subtract(const Duration(days: 1, minutes: 50)),
        mode: 'single',
        strictness: 'strict',
        sets: [
          _fakeSet('reverse_lunge', 1, 6, {2: ['knee_past_ankle']}),
          _fakeSet('reverse_lunge', 2, 6, {4: ['knee_past_ankle'], 6: ['knee_past_ankle']}),
        ],
      ),
    );
    return true;
  }

  /// [reps] reps of 2 s each; [fails] maps a rep number to its failed checks.
  static SetRecord _fakeSet(
    String exerciseId,
    int setNumber,
    int reps,
    Map<int, List<String>> fails,
  ) {
    final lunge = exerciseId.endsWith('lunge');
    return SetRecord(
      exerciseId: exerciseId,
      setNumber: setNumber,
      targetReps: reps,
      reps: [
        for (var n = 1; n <= reps; n++)
          RepRecord(
            repNumber: n,
            correct: !fails.containsKey(n),
            depth: fails.containsKey(n) ? 95.0 : 75.0,
            durationMs: 2000,
            endedAtMs: n * 3000,
            frontLeg: lunge ? (n.isOdd ? 'L' : 'R') : null,
            failedChecks: [for (final c in fails[n] ?? const <String>[]) FailedCheck(name: c)],
          ),
      ],
    );
  }

  static DateTime? _time(Object? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int);
}
