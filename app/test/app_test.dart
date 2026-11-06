import 'package:flutter_test/flutter_test.dart';
import 'package:goye/main.dart';

void main() {
  testWidgets('shows the Go-Ye welcome screen', (WidgetTester tester) async {
    await tester.pumpWidget(const GoYeApp());

    expect(find.text('Go-Ye'), findsOneWidget);
    expect(find.text('Every soul matters.'), findsOneWidget);
    expect(find.text('Pilot setup in progress'), findsOneWidget);
  });
}
