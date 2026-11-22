// Fuera de la web no se guarda nada: la sesión vive solo mientras el programa está abierto.
final Map<String, String> _memoria = {};

String? leerAlmacen(String clave) => _memoria[clave];

void escribirAlmacen(String clave, String valor) => _memoria[clave] = valor;

void borrarAlmacen(String clave) => _memoria.remove(clave);
