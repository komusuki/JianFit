import 'package:flutter/material.dart';

import '../models/exercise_info.dart';
import '../models/workout_records.dart';
import '../services/database_service.dart';
import '../services/exercise_loader.dart';
import '../widgets/number_picker.dart';

// Routine builder (roadmap Part 11): a name, then exercises in order, each
// with reps or seconds, sets and rest. Long-press and drag to reorder.
// Saves with Member C's DatabaseService.saveRoutine().
class RoutineBuilderScreen extends StatefulWidget {
  const RoutineBuilderScreen({super.key});

  @override
  State<RoutineBuilderScreen> createState() => _RoutineBuilderScreenState();
}

class _RoutineBuilderScreenState extends State<RoutineBuilderScreen> {
  final _name = TextEditingController();
  final _items = <RoutineItem>[];
  final Map<String, ExerciseInfo> _exercises = {
    for (final e in fakeExercises) e.id: e,
  };
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    // Exercise files override the fake data and add new exercises.
    ExerciseLoader.loadAll().then((r) {
      if (!mounted) return;
      setState(() {
        for (final def in r.exercises.values) {
          _exercises[def.info.id] = def.info;
        }
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving && _name.text.trim().isNotEmpty && _items.isNotEmpty;

  String _describe(RoutineItem item) {
    final target = item.targetSeconds != null
        ? '${item.targetSeconds} s'
        : '${item.targetReps} reps';
    return '$target x ${item.sets} sets, rest ${item.restSec} s';
  }

  Future<void> _addExercise() async {
    final info = await showModalBottomSheet<ExerciseInfo>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          children: [
            for (final e in _exercises.values)
              ListTile(
                title: Text(e.name),
                subtitle: Text(e.pattern),
                onTap: () => Navigator.pop(c, e),
              ),
          ],
        ),
      ),
    );
    if (info == null) return;
    final isHold = info.type == ExerciseType.hold;
    final item = await _editItem(
      info,
      RoutineItem(
        exerciseId: info.id,
        targetReps: isHold ? null : 10,
        targetSeconds: isHold ? 30 : null,
        sets: 3,
        restSec: 60,
      ),
    );
    if (item != null) setState(() => _items.add(item));
  }

  Future<void> _changeItem(int index) async {
    final item = _items[index];
    final info = _exercises[item.exerciseId];
    if (info == null) return;
    final changed = await _editItem(info, item);
    if (changed != null) setState(() => _items[index] = changed);
  }

  /// The three pickers in a bottom sheet. Null if closed without Done.
  Future<RoutineItem?> _editItem(ExerciseInfo info, RoutineItem start) {
    final isHold = info.type == ExerciseType.hold;
    var target =
        (isHold ? start.targetSeconds : start.targetReps) ??
            (isHold ? 30 : 10);
    var sets = start.sets;
    var rest = start.restSec;
    return showModalBottomSheet<RoutineItem>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(info.name, style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 8),
                NumberPicker(
                  label: isHold ? 'Seconds per set' : 'Correct reps per set',
                  value: target,
                  min: isHold ? 10 : 1,
                  max: isHold ? 300 : 50,
                  step: isHold ? 5 : 1,
                  onChanged: (v) => setSheet(() => target = v),
                ),
                NumberPicker(
                  label: 'Sets',
                  value: sets,
                  min: 1,
                  max: 10,
                  step: 1,
                  onChanged: (v) => setSheet(() => sets = v),
                ),
                NumberPicker(
                  label: 'Rest between sets (seconds)',
                  value: rest,
                  min: 15,
                  max: 180,
                  step: 15,
                  onChanged: (v) => setSheet(() => rest = v),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    c,
                    RoutineItem(
                      exerciseId: info.id,
                      targetReps: isHold ? null : target,
                      targetSeconds: isHold ? target : null,
                      sets: sets,
                      restSec: rest,
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DatabaseService.instance.saveRoutine(
        Routine(name: _name.text.trim(), items: List.of(_items)),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New routine'),
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExercise,
        icon: const Icon(Icons.add),
        label: const Text('Add exercise'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Routine name',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_items.isEmpty)
            const Expanded(
              child: Center(child: Text('Add exercises with the button below.')),
            )
          else
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: _items.length,
                onReorderItem: (from, to) => setState(() {
                  _items.insert(to, _items.removeAt(from));
                }),
                itemBuilder: (context, i) {
                  final item = _items[i];
                  return ListTile(
                    key: ObjectKey(item),
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(
                      _exercises[item.exerciseId]?.name ?? item.exerciseId,
                    ),
                    subtitle: Text(_describe(item)),
                    onTap: () => _changeItem(i),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => setState(() => _items.removeAt(i)),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}