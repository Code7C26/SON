import 'package:flutter_test/flutter_test.dart';
import 'package:son_tecnico/main.dart';

void main() {
  testWidgets('La app arranca en la pantalla de login', (WidgetTester tester) async {
    await tester.pumpWidget(const SonApp());

    expect(find.text('Ingresá a tu jornada'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
  });
}
