import 'package:flutter/material.dart';

import '../models/workout_records.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/workout_launcher.dart';
import 'exercise_detail_screen.dart';
import 'routine_builder_screen.dart';
import 'routine_list_screen.dart';

// Today tab (design H): this week's workout days, the last used routine with
// Start routine, and quick start for single exercises.
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.database,
    required this.onShowExercises,
  });

  final DatabaseService database;

  /// Switches to the Exercises tab.
  final VoidCallback onShowExercises;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  bool _loaded = false;
  Routine? _routine;
  Set<DateTime> _workoutDays = {};
  List<CatalogEntry> _catalog = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  Future<void> _load() async {
    Routine? routine;
    var days = <DateTime>{};
    var catalog = <CatalogEntry>[];
    try {
      final routines = await widget.database.listRoutines();
      final lastId = await SettingsService.loadLastRoutineId();
      // The routine started last; if none, the newest one.
      for (final r in routines) {
        if (r.id == lastId) routine = r;
      }
      if (routine == null && routines.isNotEmpty) routine = routines.first;
      final sessions = await widget.database.listSessions();
      days = {for (final s in sessions) _day(s.startedAt)};
    } catch (e) {
      debugPrint('Today could not load routines or sessions: $e');
    }
    try {
      catalog = await loadCatalog();
    } catch (e) {
      debugPrint('Today could not load exercises: $e');
    }
    if (!mounted) return;
    setState(() {
      _routine = routine;
      _workoutDays = days;
      _catalog = catalog;
      _loaded = true;
    });
  }

  /// Opens a screen, then reloads (a workout or a new routine may change
  /// what Today shows).
  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  Future<void> _start(Routine r) async {
    await startRoutine(context, r);
    _load();
  }

  String _name(String exerciseId) {
    for (final (info, _) in _catalog) {
      if (info.id == exerciseId) return info.name;
    }
    return exerciseId;
  }

  static String _describe(RoutineItem i) {
    if (i.targetSeconds != null) {
      return '${i.sets} ${i.sets == 1 ? 'hold' : 'holds'} of '
          '${i.targetSeconds} s, ${i.restSec} s rest';
    }
    return '${i.sets} ${i.sets == 1 ? 'set' : 'sets'} of '
        '${i.targetReps}, ${i.restSec} s rest';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            'Today',
                            style: text.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          '${_weekdays[now.weekday - 1]}, '
                          '${_months[now.month - 1]} ${now.day}',
                          style: text.titleSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _WeekStrip(today: _day(now), workoutDays: _workoutDays),
                    const SizedBox(height: 20),
                    _routineCard(context),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Quick start',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: widget.onShowExercises,
                          child: Text('All ${_catalog.length} exercises'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (info, def) in _catalog)
                          ActionChip(
                            label: Text(info.name),
                            onPressed: () => _open(
                              ExerciseDetailScreen(
                                exercise: info,
                                definition: def,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// The last used routine with its steps and Start routine, or an invitation
  /// to build one.
  Widget _routineCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final routine = _routine;
    final onCard = scheme.onInverseSurface;
    final startStyle = FilledButton.styleFrom(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      minimumSize: const Size.fromHeight(52),
      textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: routine == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'No routine yet',
                  style: text.titleLarge?.copyWith(
                    color: onCard,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Put your exercises, sets and rest together once, then '
                  'start them here with one tap.',
                  style: text.bodyMedium?.copyWith(color: onCard),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: startStyle,
                  onPressed: () => _open(const RoutineBuilderScreen()),
                  child: const Text('Build a routine'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your routine',
                            style: text.labelLarge?.copyWith(color: onCard),
                          ),
                          Text(
                            routine.name,
                            style: text.titleLarge?.copyWith(
                              color: onCard,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: onCard),
                      onPressed: () => _open(const RoutineListScreen()),
                      child: const Text('All routines'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < routine.items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        _StepNumber(number: i + 1, filled: i == 0),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _name(routine.items[i].exerciseId),
                                style: text.titleSmall?.copyWith(
                                  color: onCard,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _describe(routine.items[i]),
                                style: text.bodyMedium?.copyWith(color: onCard),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 2),
                FilledButton(
                  style: startStyle,
                  onPressed: () => _start(routine),
                  child: const Text('Start routine'),
                ),
              ],
            ),
    );
  }
}

/// Monday to Sunday of this week: today filled, workout days highlighted.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.today, required this.workoutDays});

  final DateTime today;
  final Set<DateTime> workoutDays;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(
              builder: (context) {
                final day = DateTime(
                  today.year,
                  today.month,
                  today.day - (today.weekday - 1) + i,
                );
                final isToday = day == today;
                final worked = workoutDays.contains(day);
                final bg = isToday
                    ? scheme.primary
                    : worked
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest;
                final fg = isToday
                    ? scheme.onPrimary
                    : worked
                    ? scheme.onSecondaryContainer
                    : scheme.onSurface;
                return Semantics(
                  label:
                      '${_days[i]} ${day.day}'
                      '${isToday ? ', today' : ''}'
                      '${worked ? ', worked out' : ''}',
                  excludeSemantics: true,
                  child: Column(
                    children: [
                      Text(
                        _letters[i],
                        style: text.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bg,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${day.day}',
                          style: text.labelLarge?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// A routine step's number: the first step filled, the rest outlined.
class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.number, required this.filled});

  final int number;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? scheme.secondaryContainer : null,
        shape: BoxShape.circle,
        border: filled
            ? null
            : Border.all(color: scheme.secondaryContainer, width: 2),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: filled ? scheme.onSecondaryContainer : scheme.onInverseSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
