import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:son_admin/main.dart';
import 'package:son_admin/services/sesion.dart';

void main() {
  testWidgets('Sin sesión guardada, el panel arranca en la pantalla de login', (WidgetTester tester) async {
    SesionAdmin.cerrar();
    await tester.pumpWidget(const SonAdmin());
    await tester.pumpAndSettle();

    expect(find.byType(PantallaLogin), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });

  test('La sesión se recuerda y se borra al cerrar sesión', () {
    SesionAdmin.cerrar();
    expect(SesionAdmin.restaurar(), isNull);

    SesionAdmin.guardar('token-de-prueba', {'id': 1, 'nombre': 'Admin', 'email': 'a@b.com', 'rol': 'comercial'});
    SesionAdmin.token = null; // como si se hubiera refrescado la página
    final admin = SesionAdmin.restaurar();
    expect(admin?['email'], 'a@b.com');
    expect(admin?['rol'], 'comercial');
    expect(SesionAdmin.token, 'token-de-prueba');

    SesionAdmin.guardarPantalla('clientes');
    expect(SesionAdmin.pantallaGuardada(), 'clientes');

    SesionAdmin.cerrar();
    expect(SesionAdmin.restaurar(), isNull);
    expect(SesionAdmin.pantallaGuardada(), isNull);
  });
}
