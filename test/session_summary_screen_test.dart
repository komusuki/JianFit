// Tests for lib/screens/session_summary_screen.dart. Owner: Member C.
//   flutter test test/session_summary_screen_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianfit/models/workout_records.dart';
import 'package:jianfit/screens/session_summary_screen.dart';
import 'package:jianfit/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('shows a saved session from the database', (tester) async {
    // Database work is real async, so it runs outside the test's fake clock.
    final summary = await tester.runAsync(() async {
      final db = DatabaseService(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      await db.seedFakeData(now: DateTime(2026, 11, 15, 12));
      final squats = (await db.listSessions()).last; // 3 days ago: squats
      final s = await db.getSummary(squats.id);
      await db.close();
      return s;
    });
    await tester.pumpWidget(_wrap(SessionSummaryView(summary: summary!)));

    expect(find.text('16 correct of 20 attempted'), findsOneWidget);
    expect(find.text('Form accuracy: 80%'), findsOneWidget);
    expect(
      find.text('Most common mistake: Heel lift (3 reps)'),
      findsOneWidget,
    );
    expect(find.text('Bodyweight squat, set 1'), findsOneWidget);
    expect(find.text('9 correct of 10 attempted (target 10)'), findsOneWidget);
    expect(find.text('7 correct of 10 attempted (target 10)'), findsOneWidget);
  });

  testWidgets('a hold-only session shows seconds and no accuracy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SessionSummaryView(
          summary: SessionSummary(
            sessionId: 1,
            correctReps: 0,
            attemptedReps: 0,
            sets: [
              SetSummary(
                exerciseId: 'forearm_plank',
                setNumber: 1,
                correctReps: 0,
                attemptedReps: 0,
                targetSeconds: 30,
                holdSeconds: 27.5,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('No reps in this session'), findsOneWidget);
    expect(find.textContaining('Form accuracy'), findsNothing);
    expect(find.textContaining('Most common mistake'), findsNothing);
    expect(find.text('Forearm plank, set 1'), findsOneWidget);
    expect(find.text('27 of 30 seconds held'), findsOneWidget);
  });
}
