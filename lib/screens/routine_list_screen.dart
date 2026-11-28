import 'package:flutter/material.dart';

import '../models/workout_records.dart';
import '../services/database_service.dart';
import '../services/workout_launcher.dart';
import 'routine_builder_screen.dart';

// Custom Workout Mode: the saved routines (Member C's database).
// New routine opens the builder. Tapping a routine runs it (routine runner
// in workout_launcher.dart).
class RoutineListScreen extends StatefulWidget {
  const RoutineListScreen({super.key});

  @override
  State<RoutineListScreen> createState() => _RoutineListScreenState();
}

class _RoutineListScreenState extends State<RoutineListScreen> {
  List<Routine>? _routines;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final routines = await DatabaseService.instance.listRoutines();
    if (mounted) setState(() => _routines = routines);
  }

  Future<void> _create() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RoutineBuilderScreen()),
    );
    if (saved == true) _load();
  }

  Future<void> _edit(Routine r) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RoutineBuilderScreen(routine: r)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Routine r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${r.name}"?'),
        content: const Text('Past sessions stay in your history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseService.instance.deleteRoutine(r.id!);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final routines = _routines;
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Workout')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New routine'),
      ),
      body: routines == null
          ? const Center(child: CircularProgressIndicator())
          : routines.isEmpty
          ? const Center(
              child: Text('No routines yet. Tap New routine to build one.'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                for (final r in routines)
                  Card(
                    child: ListTile(
                      title: Text(r.name),
                      subtitle: Text(
                        '${r.items.length} exercises, '
                        '${r.items.fold(0, (sum, i) => sum + i.sets)} sets',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                            onPressed: () => _edit(r),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                            onPressed: () => _delete(r),
                          ),
                        ],
                      ),
                      onTap: () => startRoutine(context, r),
                    ),
                  ),
              ],
            ),
    );
  }
}
