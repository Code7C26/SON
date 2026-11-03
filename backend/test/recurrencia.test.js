const assert = require('assert');
const { fechasSiguientes } = require('../src/recurrencia');

const base = {
    fecha_asignada: '2026-11-02',
    recurrencia_valor: 1,
    recurrencia_tipo: 'semana',
    termina_condicion: 'Repeticiones',
    termina_repeticiones: 4,
};

const semanas = fechasSiguientes(base, '2026-10-28');
assert.deepStrictEqual(semanas, ['2026-11-09', '2026-11-16', '2026-11-23'], '4 visitas en total: la primera más tres');

const hasta = fechasSiguientes({
    ...base,
    recurrencia_tipo: 'día',
    termina_condicion: 'Fecha',
    termina_fecha: '2026-11-05',
}, '2026-10-28');
assert.deepStrictEqual(hasta, ['2026-11-03', '2026-11-04', '2026-11-05']);

const nunca = fechasSiguientes({
    ...base,
    termina_condicion: 'Nunca',
}, '2026-11-02');
assert.strictEqual(nunca[0], '2026-11-09');
assert.ok(nunca[nunca.length - 1] <= '2027-05-02', 'seis meses hacia adelante');
assert.ok(nunca.length >= 20);

const unaSola = fechasSiguientes({ ...base, termina_repeticiones: 1 }, '2026-10-28');
assert.deepStrictEqual(unaSola, []);

console.log('RESULTADO: recurrencia OK');
