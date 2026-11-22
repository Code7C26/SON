import 'package:flutter_test/flutter_test.dart';
import 'package:son_admin/i18n/idioma.dart';

void main() {
  tearDown(() => controlIdioma.establecer('es', avisar: false));

  test('en español devuelve el texto tal cual', () {
    expect(tr('Órdenes'), 'Órdenes');
  });

  test('traduce textos fijos, mayúsculas y minúsculas', () {
    controlIdioma.establecer('en', avisar: false);
    expect(tr('Órdenes'), 'Orders');
    expect(tr('Cerrar sesión'), 'Sign out');
    expect(tr('PENDIENTE'), 'PENDING');
    expect(tr('pendiente'), 'pending');
    expect(tr('Total: '), 'Total: ');
  });

  test('traduce plantillas con partes variables', () {
    controlIdioma.establecer('en', avisar: false);
    expect(tr('12 clientes'), '12 clients');
    expect(tr('Hola, Francina.'), 'Hi, Francina.');
    expect(tr('3 de 5'), '3 of 5');
    expect(tr('jueves 20 de noviembre'), 'Thursday, November 20');
    expect(tr('Gasto guardado. Le llega a Administración.'), 'Expense saved. It goes to Administration.');
  });

  test('no toca datos que no son textos de la app', () {
    controlIdioma.establecer('en', avisar: false);
    expect(tr('Juan de la Cruz'), 'Juan de la Cruz');
    expect(tr('Clínica del Sol'), 'Clínica del Sol');
  });

  test('titulares de dos partes', () {
    controlIdioma.establecer('en', avisar: false);
    expect(trPar('Órdenes de', 'trabajo'), ('Work', 'orders'));
    expect(trPar('Análisis y', 'estadísticas'), ('Analytics and', 'statistics'));
  });
}
