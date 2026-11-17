// Tests for lib/screens/history_screen.dart. Owner: Member C.
//   flutter test test/history_screen_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianfit/models/workout_records.dart';
import 'package:jianfit/screens/history_screen.dart';
import 'package:jianfit/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('lists saved sessions newest first', (tester) async {
    // Database work is real async, so it runs outside the test's fake clock.
    final sessions = await tester.runAsync(() async {
      final db = DatabaseService(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      await db.seedFakeData(now: DateTime(2026, 11, 15, 12));
      final list = await db.listSessions();
      await db.close();
      return list;
    });
    await tester.pumpWidget(_wrap(HistoryView(sessions: sessions!)));

    final subtitles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.subtitle! as Text).data)
        .toList();
    expect(subtitles, [
      'Nov 14, 11:00 AM\n9 correct of 12 attempted, Strict',
      'Nov 13, 9:00 AM\n14 correct of 16 attempted, Standard',
      'Nov 12, 10:00 AM\n16 correct of 20 attempted, Standard',
    ]);
    expect(find.text('Reverse lunge'), findsOneWidget);
    expect(find.text('Bodyweight squat'), findsOneWidget);
  });

  testWidgets('tapping a session passes it to onOpen', (tester) async {
    final session = SessionListItem(
      id: 7,
      startedAt: DateTime(2026, 11, 16, 18, 5),
      mode: 'single',
      strictness: 'beginner',
      correctReps: 0,
      attemptedReps: 0,
      exerciseIds: const ['forearm_plank'],
    );
    SessionListItem? opened;
    await tester.pumpWidget(
      _wrap(HistoryView(sessions: [session], onOpen: (s) => opened = s)),
    );

    expect(find.text('Forearm plank'), findsOneWidget);
    expect(find.text('Nov 16, 6:05 PM\nNo reps, Beginner'), findsOneWidget);
    await tester.tap(find.text('Forearm plank'));
    expect(opened?.id, 7);
  });

  testWidgets('no sessions shows a message', (tester) async {
    await tester.pumpWidget(_wrap(const HistoryView(sessions: [])));
    expect(find.textContaining('No workouts yet'), findsOneWidget);
  });
}
