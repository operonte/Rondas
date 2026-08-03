import 'package:flutter_test/flutter_test.dart';
import 'package:rondas/main.dart';
import 'package:rondas/services/auth_service.dart';

void main() {
  testWidgets('Smoke test de inicio RondasApp', (WidgetTester tester) async {
    await tester.pumpWidget(const RondasApp(initialRole: UserRole.none));
    expect(find.byType(RondasApp), findsOneWidget);
  });
}
