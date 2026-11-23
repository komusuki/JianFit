// Tests for lib/services/overload.dart. Owner: Member C.
//   flutter test test/overload_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:jianfit/services/overload.dart';

void main() {
  test('no warning below target plus 5 attempts', () {
    expect(warnTooManyReps(attempted: 14, correct: 7, target: 10), isNull);
  });

  test('warns at exactly target plus 5 attempts', () {
    expect(
      warnTooManyReps(attempted: 15, correct: 7, target: 10),
      'That\'s 15 reps for a target of 10. Take a break or lower your target.',
    );
  });

  test('keeps warning as attempts go on', () {
    expect(warnTooManyReps(attempted: 18, correct: 9, target: 10), isNotNull);
  });

  test('no warning once the target is reached', () {
    expect(warnTooManyReps(attempted: 20, correct: 10, target: 10), isNull);
  });

  test('no warning without a target (holds)', () {
    expect(warnTooManyReps(attempted: 0, correct: 0, target: 0), isNull);
  });
}
