import 'package:flutter_test/flutter_test.dart';
import 'package:son_tecnico/services/almacen.dart';

// En los tests no hay plugin de path_provider: es exactamente el error
// "MissingPluginException" que se veía en el celular. La app no debe romperse.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('si el almacenamiento del dispositivo falla, guarda en memoria y no lanza errores', () async {
    await Almacen.escribir('cola/1_estado.json', {'a': 1});
    await Almacen.escribir('cola/2_informe.json', {'b': 2});
    expect(await Almacen.leer('cola/1_estado.json'), {'a': 1});
    expect(await Almacen.listar('cola'), ['1_estado.json', '2_informe.json']);

    await Almacen.mover('cola/1_estado.json', 'cola_fallida/1_estado.json');
    expect(await Almacen.listar('cola'), ['2_informe.json']);
    expect(await Almacen.listar('cola_fallida'), ['1_estado.json']);

    await Almacen.borrar('cola/2_informe.json');
    expect(await Almacen.leer('cola/2_informe.json'), isNull);
  });
}
