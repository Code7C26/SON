// Genera un presupuesto de ejemplo en PDF para revisar el diseño a simple vista (no usa servidor ni base).
// Uso:  node test/muestra-presupuesto.js [largo]      (con "largo" arma uno de varias hojas)
const fs = require('fs');
const path = require('path');
const { crearPresupuestoPdf } = require('../src/presupuesto_pdf');
const { calcularPresupuesto } = require('../src/presupuesto_calculo');
const { CONFIG_POR_DEFECTO } = require('../src/tarifario');
const { nombreDelMes } = require('../src/indexacion');

const largo = process.argv[2] === 'largo';
const destino = path.join(__dirname, largo ? 'muestra-presupuesto-largo.pdf' : 'muestra-presupuesto.pdf');

const alcanceSHT = [
    'Visita mensual de un Licenciado en Higiene y Seguridad en el Trabajo al establecimiento.',
    'Asesoramiento permanente al empleador en el cumplimiento de la Ley 19.587, el Decreto 351/79 y la Resolución 905/15.',
    'Confección y actualización del legajo técnico, registros y planillas exigidos por la normativa vigente.',
    'Investigación de accidentes e incidentes y seguimiento de las medidas correctivas.',
].join('\n');

const complementarios = [
    { descripcion: 'Programa Integral de Prevención de Riesgos Laborales (PPRL)', cantidad: 1, precioUnitario: 280000, alcance: 'Confección del programa anual de prevención, con cronograma de actividades y responsables.' },
    { descripcion: 'Capacitaciones anuales al personal (a coordinar con la empresa)', cantidad: 4, precioUnitario: 89960, alcance: '' },
    { descripcion: 'Estudio de iluminación (Res. 84/12) en puestos de trabajo', cantidad: 1, precioUnitario: 93900, alcance: '' },
    { descripcion: 'Medición de puesta a tierra y continuidad (Res. 900/15)', cantidad: 2, precioUnitario: 78500, alcance: 'Medición en todas las instalaciones eléctricas del establecimiento, con protocolo firmado por el profesional.' },
    { descripcion: 'Estudio de Carga de Fuego y Plan de Evacuación', cantidad: 1, precioUnitario: 480000, alcance: '' },
].map((c) => ({ ...c, periodicidad: 'unico', prorratearMeses: 12, bonificable: false }));

const items = [
    { descripcion: 'Servicio mensual de Higiene y Seguridad en el Trabajo, categoría C (hasta 15 trabajadores)', cantidad: 1, precioUnitario: 521590, alcance: alcanceSHT, periodicidad: 'mensual', prorratearMeses: null, bonificable: true },
    { descripcion: 'Traslado del profesional (12 km por visita)', cantidad: 12, precioUnitario: 390, alcance: '', periodicidad: 'mensual', prorratearMeses: null, bonificable: true },
    ...complementarios,
    { descripcion: 'Relevamiento inicial de riesgos y diagnóstico de situación', cantidad: 1, precioUnitario: 150000, alcance: '', periodicidad: 'unico', prorratearMeses: null, bonificable: false },
].map((item, i) => ({ orden: i + 1, tarifaId: null, precioOrigen: 'manual', valorBase: null, mesBase: null, costeo: [], ...item }));

if (largo) {
    for (let i = 1; i <= 22; i++) {
        items.push({
            orden: items.length + 1, tarifaId: null, precioOrigen: 'manual', valorBase: null, mesBase: null, costeo: [],
            descripcion: `Servicio adicional número ${i} con una descripción lo bastante larga para que se parta en más de un renglón dentro de la tabla`,
            cantidad: i % 4 === 0 ? 3 : 1, precioUnitario: 10000 * i, alcance: i % 5 === 0 ? 'Detalle del alcance de este servicio. '.repeat(12) : '',
            periodicidad: i % 2 ? 'mensual' : 'unico', prorratearMeses: null, bonificable: true,
        });
    }
}

const bonificacion = 0.3;
const calculo = calcularPresupuesto({ items, bonificacion, iva: 0.21, margenMinimo: 0.2, margenIdeal: 0.35 });

crearPresupuestoPdf(fs.createWriteStream(destino), {
    config: CONFIG_POR_DEFECTO,
    etiqueta: '3611 - act',
    fecha: '2026-10-27',
    cliente: {
        razonSocial: 'REFIALT S.A.', direccion: 'Ruta Nacional 36 Km 601', localidad: 'Río Cuarto', provincia: 'Córdoba',
        telefono: '358 456-7890', email: 'compras@refialt.example', cuit: '30-71234567-1', atencion: 'Ing. Valentina Pérez',
    },
    formaPago: CONFIG_POR_DEFECTO.textos.forma_pago,
    plazoEntrega: CONFIG_POR_DEFECTO.textos.plazo_entrega,
    validez: CONFIG_POR_DEFECTO.textos.validez,
    referencia: 'El valor se actualiza todos los meses según el IPC publicado por el INDEC.',
    observaciones: 'El presupuesto es actualizable al momento de la acreditación del pago.\nLos servicios complementarios se facturan en 12 cuotas mensuales junto con el servicio base.',
    items,
    calculo,
    mesReferencia: nombreDelMes('2026-10'),
}).then(() => console.log(`Listo: ${destino}`)).catch((error) => { console.error(error); process.exit(1); });
