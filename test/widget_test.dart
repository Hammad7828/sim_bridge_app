import 'package:flutter_test/flutter_test.dart';
import 'package:sim_bridge_app/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SimBridgeApp());
    expect(find.byType(SimBridgeApp), findsOneWidget);
  });
}