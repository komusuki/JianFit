import 'package:flutter_test/flutter_test.dart';
import 'package:jianfit/main.dart';

void main() {
  testWidgets('Home screen shows the main options', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('JianFit'), findsOneWidget);
    expect(find.text('Single Exercise'), findsOneWidget);
    expect(find.text('Custom Workout'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
  });
}