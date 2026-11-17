// History screen (roadmap Part 12). Owner: Member C.
// Every saved session, newest first. Tapping one opens its summary.
// Member B connects the Home screen's History card to this screen.

import 'package:flutter/material.dart';

import '../models/workout_records.dart';
import '../services/database_service.dart';
import 'session_summary_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.database});

  final DatabaseService database;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final Future<List<SessionListItem>> _sessions = widget.database
      .listSessions();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: FutureBuilder<List<SessionListItem>>(
        future: _sessions,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('History could not be loaded.'));
          }
          return HistoryView(
            sessions: snapshot.data ?? const [],
            onOpen: (s) => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SessionSummaryScreen(
                  database: widget.database,
                  sessionId: s.id,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The list itself, without the loading. Separate so tests can show it
/// directly.
class HistoryView extends StatelessWidget {
  const HistoryView({super.key, required this.sessions, this.onOpen});

  final List<SessionListItem> sessions;
  final ValueChanged<SessionListItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No workouts yet. Finished workouts show up here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final s in sessions)
          Card(
            child: ListTile(
              title: Text(_title(s)),
              subtitle: Text(
                '${_when(s.startedAt)}\n${_result(s)}, ${_cap(s.strictness)}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpen == null ? null : () => onOpen!(s),
            ),
          ),
      ],
    );
  }
}

String _title(SessionListItem s) => s.exerciseIds.isEmpty
    ? 'Workout'
    : s.exerciseIds.map(exerciseName).join(', ');

String _result(SessionListItem s) => s.attemptedReps == 0
    ? 'No reps'
    : '${s.correctReps} correct of ${s.attemptedReps} attempted';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// For example 'Nov 14, 11:00 AM'.
String _when(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  final half = t.hour < 12 ? 'AM' : 'PM';
  return '${_months[t.month - 1]} ${t.day}, $hour:$minute $half';
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
