const assert = require('assert');
const { interpretarFiltros, normalizarChecklist, topFallas, cumplimiento, variacion, armarVista } = require('../src/analisis');

const noviembre = new Date('2026-11-15T15:00:00Z');
const mes = interpretarFiltros({ periodo: 'mes' }, noviembre);
assert.deepStrictEqual([mes.desde, mes.hasta, mes.anteriorDesde, mes.anteriorHasta, mes.comparacion], ['2026-11-01', '2026-11-30', '2026-10-01', '2026-10-31', 'vs mes anterior']);

const hoy = interpretarFiltros({ periodo: 'hoy' }, noviembre);
assert.deepStrictEqual([hoy.desde, hoy.hasta, hoy.anteriorDesde, hoy.anteriorHasta], ['2026-11-15', '2026-11-15', '2026-11-14', '2026-11-14']);

const semana = interpretarFiltros({ periodo: '7d' }, noviembre);
assert.deepStrictEqual([semana.desde, semana.hasta, semana.anteriorDesde, semana.anteriorHasta], ['2026-11-09', '2026-11-15', '2026-11-02', '2026-11-08']);

const trimestre = interpretarFiltros({ periodo: 'trimestre' }, noviembre);
assert.deepStrictEqual([trimestre.desde, trimestre.hasta, trimestre.anteriorDesde, trimestre.anteriorHasta], ['2026-10-01', '2026-12-31', '2026-07-01', '2026-09-30']);

const enero = interpretarFiltros({ periodo: 'trimestre' }, new Date('2026-01-15T15:00:00Z'));
assert.deepStrictEqual([enero.anteriorDesde, enero.anteriorHasta], ['2025-10-01', '2025-12-31']);

const marzo = interpretarFiltros({ periodo: 'mes' }, new Date('2024-03-10T15:00:00Z'));
assert.deepStrictEqual([marzo.anteriorDesde, marzo.anteriorHasta], ['2024-02-01', '2024-02-29']);

const propio = interpretarFiltros({ periodo: 'custom', desde: '2026-11-01', hasta: '2026-11-03' }, noviembre);
assert.deepStrictEqual([propio.desde, propio.hasta, propio.anteriorDesde, propio.anteriorHasta], ['2026-11-01', '2026-11-03', '2026-10-29', '2026-10-31']);
assert.strictEqual(interpretarFiltros({ periodo: 'custom', desde: '2026-11-03', hasta: '2026-11-01' }, noviembre).error, 'Elegí un rango de fechas válido');
assert.strictEqual(interpretarFiltros({ periodo: 'raro' }, noviembre).status, 400);
assert.strictEqual(interpretarFiltros({ empresaId: 'abc' }, noviembre).status, 400);

const checklist = normalizarChecklist([
    { tarea: ' Revisar matafuegos ', hecho: false },
    { tarea: '', hecho: true },
    { tarea: 'Luces', hecho: 'true' },
]);
assert.deepStrictEqual(checklist, [
    { tarea: 'Revisar matafuegos', hecho: false },
    { tarea: 'Luces', hecho: true },
]);
assert.strictEqual(normalizarChecklist('no'), null);

const listas = [
    [{ tarea: 'Revisar matafuegos', hecho: false }, { tarea: 'Señalización', hecho: true }],
    [{ tarea: 'revisar matafuegos', hecho: false }, { tarea: 'Luces de emergencia', hecho: false }],
    [{ tarea: 'Revisar matafuegos', hecho: true }],
];
assert.strictEqual(cumplimiento(listas).porcentaje, 40);
assert.deepStrictEqual(topFallas(listas).map((fila) => [fila.tarea, fila.fallos, fila.total]), [
    ['Revisar matafuegos', 2, 3],
    ['Luces de emergencia', 1, 1],
]);
assert.strictEqual(variacion(12, 10), 20);
assert.strictEqual(variacion(8, 10), -20);
assert.strictEqual(variacion(0, 0), 0);
assert.strictEqual(variacion(5, 0), null);

const vista = armarVista({
    filtros: { periodo: 'mes', desde: '2026-11-01', hasta: '2026-11-30', comparacion: 'vs mes anterior', hoy: '2026-11-15' },
    ordenesAnteriores: 2,
    clientes: [{ id: 4, nombre: 'Acerbon SRL' }],
    tecnicos: [{ id: 3, nombre: 'Juan Pérez' }],
    ordenes: [
        { id: 7, estado: 'Completada', fecha: '2026-11-02', tecnico_id: 3, tecnico: 'Juan Pérez', empresa_id: 4, cliente: 'Acerbon SRL', minutos: 90, comentarios_cierre: ' Recargar extintores ', checklist_cierre: [{ tarea: 'Matafuegos', hecho: false }, { tarea: 'Luces', hecho: true }], solicitud_id: null },
        { id: 8, estado: 'Pendiente', fecha: '2026-11-01', tecnico_id: 3, tecnico: 'Juan Pérez', empresa_id: 4, cliente: 'Acerbon SRL', minutos: null, comentarios_cierre: null, checklist_cierre: null },
        { id: 9, estado: 'Pendiente', fecha: '2026-11-20', tecnico_id: 4, tecnico: 'Ana Gómez', empresa_id: 5, cliente: 'Otra SA', minutos: null, comentarios_cierre: '   ', checklist_cierre: null },
        { id: 10, estado: 'Completada', fecha: '2026-11-10', tecnico_id: 4, tecnico: 'Ana Gómez', empresa_id: 5, cliente: 'Otra SA', minutos: 30, comentarios_cierre: null, checklist_cierre: null },
    ],
    encuestas: [
        { puntaje: 5, comentario: 'Bien', cliente: 'Acerbon SRL', tecnico: 'Juan Pérez', tecnico_id: 3, respondida_en: '2026-11-02T13:00:00Z', enviada_en: '2026-11-02T13:00:00Z' },
        { puntaje: null, comentario: null, cliente: 'Otra SA', tecnico: 'Ana Gómez', tecnico_id: 4, respondida_en: null, enviada_en: '2026-11-10T13:00:00Z' },
    ],
});

assert.strictEqual(vista.kpis.ordenes, 4);
assert.strictEqual(vista.kpis.variacion, 100);
assert.strictEqual(vista.kpis.pendientes, 2);
assert.strictEqual(vista.kpis.vencidas, 1);
assert.strictEqual(vista.kpis.checklist, 50);
assert.strictEqual(vista.kpis.completadas, 2);
assert.strictEqual(vista.kpis.tasaCierre, 50);
assert.strictEqual(vista.kpis.promedioMinutos, 60);
assert.strictEqual(vista.comentarios.length, 1);
assert.strictEqual(vista.comentarios[0].texto, 'Recargar extintores');
assert.strictEqual(vista.fallas[0].tarea, 'Matafuegos');
const juan = vista.tecnicos.find((fila) => fila.nombre === 'Juan Pérez');
assert.strictEqual(juan.calificacion, 5);
assert.strictEqual(juan.promedioMinutos, 90);
assert.strictEqual(juan.completadas, 1);
assert.strictEqual(juan.asignadas, 2);
assert.deepStrictEqual(vista.encuestas.distribucion, [0, 0, 0, 0, 1]);
assert.strictEqual(vista.encuestas.enviados, 2);
assert.strictEqual(vista.encuestas.respondidas, 1);
assert.strictEqual(vista.encuestas.tasa, 50);
assert.strictEqual(vista.serie.modo, 'semana');
assert.ok(vista.serie.puntos.some((punto) => punto.ordenes > 0));
assert.strictEqual(vista.porCliente.find((fila) => fila.nombre === 'Acerbon SRL').completadas, 1);
const trimestreVista = armarVista({
    filtros: { periodo: 'trimestre', desde: '2026-10-01', hasta: '2026-12-31', comparacion: 'vs trimestre anterior', hoy: '2026-11-15' },
    ordenesAnteriores: 0,
    ordenes: [
        { id: 1, estado: 'Completada', fecha: '2026-10-28', cliente: 'Acerbon SRL', tecnico: 'Juan Pérez', tecnico_id: 3 },
        { id: 2, estado: 'Pendiente', fecha: '2026-11-11', cliente: 'Acerbon SRL', tecnico: 'Juan Pérez', tecnico_id: 3 },
    ],
    encuestas: [{ puntaje: 5, comentario: 'Bien', cliente: 'Acerbon SRL', tecnico: 'Juan Pérez', tecnico_id: 3, respondida_en: '2026-10-29T03:53:00Z', enviada_en: '2026-10-29T03:53:00Z' }],
    clientes: [],
    tecnicos: [],
});
assert.strictEqual(trimestreVista.serie.modo, 'mes');
assert.strictEqual(trimestreVista.serie.puntos.find((punto) => punto.etiqueta === 'oct').completadas, 1);
assert.strictEqual(trimestreVista.kpis.completadas, 1);
assert.strictEqual(trimestreVista.encuestas.enviados, 1);
assert.strictEqual(vista.tiempos.length, 2);
assert.strictEqual(vista.opciones.clientes[0].nombre, 'Acerbon SRL');

console.log('RESULTADO: analisis OK');
