// Pruebas de las cuentas del presupuestador (sin base de datos ni servidor).
// Uso:   node --test test/
// Los números de ejemplo salen de la planilla de la empresa (tarifa CIEC de enero de 2026 y el
// ejemplo de REFIALT).
const test = require('node:test');
const assert = require('node:assert/strict');
const {
    aMes, mesesEntre, mesSiguiente, nombreDelMes, redondearIPC, factorIPC, valorActualizado, avisoIPCFaltante, mesActual, fechaDeHoy,
} = require('../src/indexacion');
const { calcularItem, calcularPresupuesto, nivelDeMargen, porcentajeLegible } = require('../src/presupuesto_calculo');

// Inflación mensual que usa la planilla (con un decimal, como la publica el INDEC).
const IPC_2026 = {
    '2026-01': 0.029, '2026-02': 0.029, '2026-03': 0.034, '2026-04': 0.026, '2026-05': 0.021,
    '2026-06': 0.019, '2026-07': 0.021, '2026-08': 0.017, '2026-09': 0.019,
};

test('aMes entiende fechas de distintas formas', () => {
    assert.equal(aMes('2026-09-15'), '2026-09');
    assert.equal(aMes('2026-09'), '2026-09');
    assert.equal(aMes('2026-09-15T10:00:00.000Z'), '2026-09');
    assert.equal(aMes(new Date(2026, 8, 15)), '2026-09');
    assert.equal(aMes('2026-13-01'), null);
    assert.equal(aMes('septiembre'), null);
    assert.equal(aMes(null), null);
    assert.equal(aMes(new Date('x')), null);
});

test('los meses pasan de diciembre a enero', () => {
    assert.equal(mesSiguiente('2026-11'), '2026-12');
    assert.equal(mesSiguiente('2026-12'), '2027-01');
    assert.deepEqual(mesesEntre('2026-11', '2027-02'), ['2026-11', '2026-12', '2027-01']);
    assert.deepEqual(mesesEntre('2026-05', '2026-05'), []);
    assert.deepEqual(mesesEntre('2026-06', '2026-05'), []);
    assert.equal(nombreDelMes('2026-09'), 'septiembre 2026');
});

test('hoy y el mes actual salen en hora argentina', () => {
    // 01:30 UTC del 1 de octubre todavía es 30 de septiembre en Argentina (UTC-3).
    const ahora = new Date('2026-10-01T01:30:00Z');
    assert.equal(fechaDeHoy(ahora), '2026-09-30');
    assert.equal(mesActual(ahora), '2026-09');
});

test('la inflación se usa con un decimal, como la publica el INDEC', () => {
    assert.equal(redondearIPC(0.028816), 0.029);
    assert.equal(redondearIPC(0.021137), 0.021);
    assert.equal(redondearIPC(0.0338262), 0.034);
});

test('el valor se actualiza mes a mes como en la planilla (280.000 de enero)', () => {
    // Valores de la fila de la planilla "Cuadro Tarifario CIEC +IPC".
    const esperado = { '2026-02': 288120, '2026-03': 296475.48, '2026-04': 306555.64632, '2026-05': 314526.09312432 };
    for (const [mes, valor] of Object.entries(esperado)) {
        const resultado = valorActualizado(280000, '2026-01', mes, IPC_2026);
        assert.equal(resultado.valor, Math.round(valor), mes);
        assert.deepEqual(resultado.faltantes, []);
    }
});

test('en el mes base el valor no cambia, y nunca se "desactualiza" hacia atrás', () => {
    assert.equal(valorActualizado(430000, '2026-01', '2026-01', IPC_2026).valor, 430000);
    assert.equal(valorActualizado(430000, '2026-05', '2026-02', IPC_2026).valor, 430000);
});

test('un presupuesto de septiembre usa la inflación de enero a agosto', () => {
    const resultado = valorActualizado(430000, '2026-01', '2026-09', IPC_2026);
    const producto = 1.029 * 1.029 * 1.034 * 1.026 * 1.021 * 1.019 * 1.021 * 1.017;
    assert.equal(resultado.valor, Math.round(430000 * producto));
    assert.ok(Math.abs(resultado.factor - 1.2135) < 0.0001, `factor ${resultado.factor}`);
    assert.deepEqual(resultado.faltantes, []);
});

test('si falta la inflación de un mes se avisa y ese mes no suma', () => {
    const sinAgosto = { ...IPC_2026 };
    delete sinAgosto['2026-08'];
    const resultado = valorActualizado(430000, '2026-01', '2026-10', sinAgosto);
    assert.deepEqual(resultado.faltantes, ['2026-08']);
    const producto = 1.029 * 1.029 * 1.034 * 1.026 * 1.021 * 1.019 * 1.021 * 1.019;
    assert.equal(resultado.valor, Math.round(430000 * producto));
    assert.match(avisoIPCFaltante(resultado.faltantes), /agosto 2026/);
    assert.equal(avisoIPCFaltante([]), null);
    assert.match(avisoIPCFaltante(['2026-08', '2026-09']), /agosto 2026 y septiembre 2026/);
});

test('lo que no se indexa se queda igual, aunque haya inflación', () => {
    assert.equal(valorActualizado(1000, '2026-01', '2026-09', IPC_2026, false).valor, 1000);
    assert.equal(valorActualizado(1000, null, '2026-09', IPC_2026).valor, 1000);
    assert.equal(valorActualizado('x', '2026-01', '2026-09', IPC_2026).valor, null);
});

test('ejemplo de REFIALT de la planilla: servicio mensual bonificado 30 % + complementarios en 12 meses', () => {
    // Servicio de HyS categoría C + 12 km, con 30 % de bonificación. Los servicios complementarios
    // (que duran un año) no se bonifican y se prorratean en 12 meses.
    const items = [
        { cantidad: 1, precioUnitario: 521590, periodicidad: 'mensual' },
        { cantidad: 12, precioUnitario: 390, periodicidad: 'mensual' },
        { cantidad: 1, precioUnitario: 280000, periodicidad: 'unico', prorratearMeses: 12, bonificable: false },
        { cantidad: 1, precioUnitario: 0, periodicidad: 'unico', prorratearMeses: 12, bonificable: false },
        { cantidad: 1, precioUnitario: 348000, periodicidad: 'unico', prorratearMeses: 12, bonificable: false },
        { cantidad: 4, precioUnitario: 89960, periodicidad: 'unico', prorratearMeses: 12, bonificable: false },
        { cantidad: 1, precioUnitario: 93900, periodicidad: 'unico', prorratearMeses: 12, bonificable: false },
        { cantidad: 2, precioUnitario: 78500, periodicidad: 'unico', prorratearMeses: 12, bonificable: false },
        { cantidad: 1, precioUnitario: 480000, periodicidad: 'unico', prorratearMeses: 12, bonificable: false },
    ];
    const sinBonificar = calcularPresupuesto({ items, bonificacion: 0 });
    // La planilla da 526.270 + 143.228,33 = 669.498,33 (acá, en pesos enteros).
    assert.equal(sinBonificar.totalMensual, 669498);
    assert.equal(sinBonificar.totalUnico, 0);

    const bonificado = calcularPresupuesto({ items, bonificacion: 0.3 });
    // La planilla da 368.389 + 143.228,33 = 511.617,33.
    assert.equal(bonificado.lineas[0].neto + bonificado.lineas[1].neto, 368389);
    assert.equal(bonificado.totalMensual, 511617);
    assert.equal(bonificado.descuentoTotal, 157881);
    assert.equal(bonificado.ivaMensual, Math.round(511617 * 0.21));
    assert.equal(bonificado.totalMensualConIva, 511617 + Math.round(511617 * 0.21));
});

test('el IVA se calcula sobre el precio ya bonificado', () => {
    const resultado = calcularPresupuesto({ items: [{ cantidad: 1, precioUnitario: 200000 }], bonificacion: 0.5 });
    assert.equal(resultado.totalMensual, 100000);
    assert.equal(resultado.ivaMensual, 21000);
    assert.equal(resultado.totalMensualConIva, 121000);
});

test('un ítem de pago único sin prorrateo va al total de pago único', () => {
    const resultado = calcularPresupuesto({
        items: [
            { cantidad: 1, precioUnitario: 100000, periodicidad: 'mensual' },
            { cantidad: 3, precioUnitario: 50000, periodicidad: 'unico' },
        ],
    });
    assert.equal(resultado.totalMensual, 100000);
    assert.equal(resultado.totalUnico, 150000);
    assert.equal(resultado.ivaUnico, 31500);
});

test('un ítem no bonificable no recibe descuento', () => {
    const linea = calcularItem({ cantidad: 2, precioUnitario: 1000, bonificable: false }, 0.5);
    assert.equal(linea.precioNetoUnitario, 1000);
    assert.equal(linea.neto, 2000);
    assert.equal(linea.descuento, 0);
    const bonificado = calcularItem({ cantidad: 2, precioUnitario: 1000 }, 0.5);
    assert.equal(bonificado.precioNetoUnitario, 500);
    assert.equal(bonificado.neto, 1000);
    assert.equal(bonificado.descuento, 1000);
});

test('la bonificación se mantiene entre 0 y 100 %', () => {
    assert.equal(calcularPresupuesto({ items: [{ cantidad: 1, precioUnitario: 1000 }], bonificacion: 1.5 }).totalMensual, 0);
    assert.equal(calcularPresupuesto({ items: [{ cantidad: 1, precioUnitario: 1000 }], bonificacion: -0.2 }).totalMensual, 1000);
    assert.equal(calcularPresupuesto({ items: [{ cantidad: 1, precioUnitario: 1000 }], bonificacion: 'abc' }).totalMensual, 1000);
});

test('los datos raros no rompen las cuentas', () => {
    const resultado = calcularPresupuesto({ items: [{ cantidad: 'x', precioUnitario: null }, {}] });
    assert.equal(resultado.totalMensual, 0);
    assert.equal(calcularPresupuesto({ items: [] }).totalMensual, 0);
    assert.equal(calcularPresupuesto({}).totalMensual, 0);
});

test('margen: avisa por debajo del 20 % y no bloquea nada', () => {
    const conCosto = (costo) => ({ cantidad: 1, precioUnitario: 1000, costeo: [{ cantidad: 1, costoUnitario: costo }] });
    assert.equal(calcularItem(conCosto(700), 0).margen.toFixed(3), '0.429');
    assert.equal(nivelDeMargen(0.4286), 'ok');
    assert.equal(nivelDeMargen(0.25), 'medio');
    assert.equal(nivelDeMargen(0.11), 'bajo');
    assert.equal(nivelDeMargen(0.2), 'medio', 'justo en el mínimo no es "bajo"');
    assert.equal(nivelDeMargen(0.35), 'ok', 'justo en el ideal es "ok"');
    assert.equal(nivelDeMargen(null), 'sin_dato');

    const bajo = calcularPresupuesto({ items: [conCosto(900)] });
    assert.equal(bajo.nivelMargen, 'bajo');
    assert.equal(bajo.avisos.length, 1);
    assert.equal(bajo.avisos[0].tipo, 'margen_bajo');
    assert.match(bajo.avisos[0].mensaje, /ítem 1/);
    assert.equal(bajo.totalMensual, 1000, 'el precio no se toca');

    const medio = calcularPresupuesto({ items: [conCosto(800)] });
    assert.equal(medio.nivelMargen, 'medio');
    assert.deepEqual(medio.avisos, []);
});

test('el margen tiene en cuenta la bonificación (el descuento achica el margen)', () => {
    const item = { cantidad: 1, precioUnitario: 1000, costeo: [{ cantidad: 1, costoUnitario: 700 }] };
    assert.equal(calcularPresupuesto({ items: [item], bonificacion: 0 }).nivelMargen, 'ok');
    const conDescuento = calcularPresupuesto({ items: [item], bonificacion: 0.3 });
    assert.equal(conDescuento.nivelMargen, 'bajo');
    assert.equal(conDescuento.margen.toFixed(3), '0.000');
});

test('el margen total solo usa los ítems con costo y las partes del costo se suman', () => {
    const resultado = calcularPresupuesto({
        items: [
            { cantidad: 1, precioUnitario: 1500, costeo: [{ cantidad: 3, costoUnitario: 100 }, { cantidad: 0.5, costoUnitario: 400 }] },
            { cantidad: 1, precioUnitario: 99999 },
        ],
    });
    assert.equal(resultado.lineas[0].costo, 500);
    assert.equal(resultado.costoTotal, 500);
    assert.equal(resultado.margen, 2);
    assert.equal(resultado.lineas[1].nivelMargen, 'sin_dato');
});

test('porcentajeLegible', () => {
    assert.equal(porcentajeLegible(0.2), '20 %');
    assert.equal(porcentajeLegible(0.355), '35,5 %');
    assert.equal(porcentajeLegible(null), '—');
});
