// Cuentas de un presupuesto. No toca la base ni la red: recibe datos y devuelve números,
// así se puede probar sola y es la única fuente de verdad (el panel y el PDF usan estos resultados).
//
// Todo se redondea a pesos enteros para que lo que se ve en pantalla, en el PDF y en los totales
// sea siempre lo mismo.
//
// Reglas (salen de la planilla de la empresa y de sus respuestas):
//  - La bonificación (%) la decide la empresa en cada presupuesto: no hay una regla fija.
//    Se aplica sobre el precio unitario de los ítems marcados como "bonificables".
//  - Un ítem puede ser mensual, de pago único, o de pago único prorrateado en N meses
//    (se suma a la cuota mensual).
//  - El margen es "precio / costo - 1" (como el markup de la planilla). Solo avisa: nunca bloquea.
//  - El IVA se calcula sobre el precio ya bonificado.

const MARGEN_MINIMO = 0.2;
const MARGEN_IDEAL = 0.35;
const IVA = 0.21;

const redondear = (numero) => Math.round(numero);

function numeroOCero(valor) {
    const numero = Number(valor);
    return Number.isFinite(numero) ? numero : 0;
}

// Costo interno de un ítem: suma de sus partes (horas de técnico, hotel, km...).
// Cada parte: { cantidad, costoUnitario }.
function costoDeItem(item) {
    const partes = Array.isArray(item.costeo) ? item.costeo : [];
    return partes.reduce((total, parte) => total + redondear(numeroOCero(parte.cantidad) * numeroOCero(parte.costoUnitario)), 0);
}

// Qué tan bueno es un margen: 'sin_dato' | 'bajo' | 'medio' | 'ok'.
function nivelDeMargen(margen, minimo = MARGEN_MINIMO, ideal = MARGEN_IDEAL) {
    if (margen === null || margen === undefined || !Number.isFinite(margen)) return 'sin_dato';
    // Se compara con redondeo a milésimas para que un 20,0 % "justo" no se marque como bajo por decimales.
    const valor = Math.round(margen * 1000) / 1000;
    if (valor < minimo) return 'bajo';
    if (valor < ideal) return 'medio';
    return 'ok';
}

function calcularItem(item, bonificacion = 0) {
    const cantidad = numeroOCero(item.cantidad);
    const precio = numeroOCero(item.precioUnitario);
    const bonificable = item.bonificable !== false;
    // El descuento se aplica al precio de una unidad: así el PDF muestra precios enteros que cierran.
    const precioNetoUnitario = bonificable ? redondear(precio * (1 - bonificacion)) : redondear(precio);
    const bruto = redondear(cantidad * precio);
    const neto = redondear(cantidad * precioNetoUnitario);
    const periodicidad = item.periodicidad === 'unico' ? 'unico' : 'mensual';
    const meses = periodicidad === 'unico' && Math.floor(numeroOCero(item.prorratearMeses)) >= 2 ? Math.floor(numeroOCero(item.prorratearMeses)) : null;

    let mensual = 0;
    let unico = 0;
    if (periodicidad === 'mensual') mensual = neto;
    else if (meses) mensual = redondear(neto / meses);
    else unico = neto;

    const costo = costoDeItem(item);
    const margen = costo > 0 ? neto / costo - 1 : null;

    return {
        cantidad,
        precioUnitario: redondear(precio),
        precioNetoUnitario,
        bruto,
        descuento: bruto - neto,
        neto,
        periodicidad,
        prorratearMeses: meses,
        mensual,
        unico,
        costo,
        margen,
    };
}

function calcularPresupuesto({ items = [], bonificacion = 0, iva = IVA, margenMinimo = MARGEN_MINIMO, margenIdeal = MARGEN_IDEAL }) {
    const porcentaje = Math.min(Math.max(numeroOCero(bonificacion), 0), 1);
    const lineas = items.map((item) => {
        const linea = calcularItem(item, porcentaje);
        return { ...linea, nivelMargen: nivelDeMargen(linea.margen, margenMinimo, margenIdeal) };
    });

    const suma = (campo) => lineas.reduce((total, linea) => total + linea[campo], 0);
    const totalMensual = suma('mensual');
    const totalUnico = suma('unico');
    const ivaMensual = redondear(totalMensual * iva);
    const ivaUnico = redondear(totalUnico * iva);

    // Margen del presupuesto: solo con los ítems que tienen costo cargado.
    const conCosto = lineas.filter((linea) => linea.costo > 0);
    const netoConCosto = conCosto.reduce((total, linea) => total + linea.neto, 0);
    const costoTotal = conCosto.reduce((total, linea) => total + linea.costo, 0);
    const margen = costoTotal > 0 ? netoConCosto / costoTotal - 1 : null;

    const avisos = [];
    lineas.forEach((linea, indice) => {
        if (linea.nivelMargen === 'bajo') {
            avisos.push({ tipo: 'margen_bajo', linea: indice, margen: linea.margen, mensaje: `El ítem ${indice + 1} queda con ${porcentajeLegible(linea.margen)} de margen, por debajo del mínimo (${porcentajeLegible(margenMinimo)}).` });
        }
    });
    const nivel = nivelDeMargen(margen, margenMinimo, margenIdeal);
    if (nivel === 'bajo' && conCosto.length > 1) {
        avisos.push({ tipo: 'margen_bajo_total', linea: null, margen, mensaje: `En total el presupuesto queda con ${porcentajeLegible(margen)} de margen, por debajo del mínimo (${porcentajeLegible(margenMinimo)}).` });
    }

    return {
        lineas,
        totalMensual,
        totalUnico,
        ivaMensual,
        ivaUnico,
        totalMensualConIva: totalMensual + ivaMensual,
        totalUnicoConIva: totalUnico + ivaUnico,
        bonificacion: porcentaje,
        descuentoTotal: suma('descuento'),
        costoTotal,
        margen,
        nivelMargen: nivel,
        avisos,
    };
}

// 0.2 -> "20 %", 0.355 -> "35,5 %"
function porcentajeLegible(fraccion) {
    if (fraccion === null || fraccion === undefined || !Number.isFinite(fraccion)) return '—';
    const valor = Math.round(fraccion * 1000) / 10;
    return `${String(valor).replace('.', ',')} %`;
}

module.exports = { MARGEN_MINIMO, MARGEN_IDEAL, IVA, calcularItem, calcularPresupuesto, costoDeItem, nivelDeMargen, porcentajeLegible };
