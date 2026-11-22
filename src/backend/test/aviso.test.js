const assert = require('assert');
const { numeroWhatsapp, listadoTareas, esHoraDeAvisar } = require('../src/campo');

assert.strictEqual(numeroWhatsapp('351 242 0832'), '5493512420832');
assert.strictEqual(numeroWhatsapp('+54 9 351 242-0832'), '5493512420832');
assert.strictEqual(numeroWhatsapp(''), null);
assert.strictEqual(numeroWhatsapp('123'), null);
assert.ok(listadoTareas(['Matafuegos', 'Luces'], '').includes('• Matafuegos'));
assert.ok(listadoTareas([], 'Revisar tablero').includes('• Revisar tablero'));

const cita = new Date(2026, 9, 29, 12, 30, 0, 0);
assert.strictEqual(esHoraDeAvisar('2026-10-29', '12:30', new Date(cita.getTime() - 60 * 1000)), true);
assert.strictEqual(esHoraDeAvisar('2026-10-29', '12:30', new Date(cita.getTime() - 61 * 1000)), false);
assert.strictEqual(esHoraDeAvisar('2026-10-29', '12:30', new Date(cita.getTime() + 60 * 1000)), true);
assert.strictEqual(esHoraDeAvisar('2026-10-29', '12:30', new Date(cita.getTime() + 3 * 60 * 1000)), false);
console.log('RESULTADO: aviso OK');
