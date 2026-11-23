import 'package:flutter_test/flutter_test.dart';
import 'package:jianfit/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // The Today tab opens the database; tests use the laptop version of it.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('The app opens on Today with the four tabs', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Exercises'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
