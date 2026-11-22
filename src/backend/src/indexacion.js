// Actualización de precios por inflación (IPC mensual del INDEC).
// Los meses se manejan como texto "AAAA-MM" para no depender de zonas horarias.
//
// Regla (la misma de la planilla de la empresa): un valor que viene de enero de 2026 se actualiza
// al mes M multiplicando por (1 + IPC) de cada mes desde enero hasta el mes anterior a M.
// Ejemplo: el valor de septiembre = valor de enero × IPC de enero, febrero, ..., agosto.

const FORMATO_MES = /^\d{4}-(0[1-9]|1[0-2])$/;
const NOMBRES_MES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

function mesValido(texto) {
    return typeof texto === 'string' && FORMATO_MES.test(texto);
}

// Date, "AAAA-MM-DD" o "AAAA-MM" -> "AAAA-MM". Cualquier otra cosa da null.
// Las fechas Date se leen con la hora local (así las entrega pg para una columna DATE).
function aMes(valor) {
    if (valor instanceof Date) {
        if (Number.isNaN(valor.getTime())) return null;
        return `${valor.getFullYear()}-${String(valor.getMonth() + 1).padStart(2, '0')}`;
    }
    if (typeof valor !== 'string') return null;
    const coincidencia = valor.trim().match(/^(\d{4})-(0[1-9]|1[0-2])(?:-(0[1-9]|[12]\d|3[01]))?(?:$|T|\s)/);
    return coincidencia ? `${coincidencia[1]}-${coincidencia[2]}` : null;
}

// Mes de hoy en Argentina, "AAAA-MM".
function mesActual(ahora = new Date()) {
    const partes = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Argentina/Buenos_Aires', year: 'numeric', month: '2-digit' }).formatToParts(ahora);
    const anio = partes.find((p) => p.type === 'year').value;
    const mes = partes.find((p) => p.type === 'month').value;
    return `${anio}-${mes}`;
}

// Fecha de hoy en Argentina, "AAAA-MM-DD".
function fechaDeHoy(ahora = new Date()) {
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Argentina/Buenos_Aires', year: 'numeric', month: '2-digit', day: '2-digit' }).format(ahora);
}

function mesSiguiente(mes) {
    const [anio, numero] = mes.split('-').map(Number);
    return numero === 12 ? `${anio + 1}-01` : `${anio}-${String(numero + 1).padStart(2, '0')}`;
}

// Meses desde "desde" (incluido) hasta "hasta" (sin incluir).
function mesesEntre(desde, hasta) {
    const lista = [];
    let actual = desde;
    while (actual < hasta && lista.length < 600) {
        lista.push(actual);
        actual = mesSiguiente(actual);
    }
    return lista;
}

// "2026-09" -> "septiembre 2026"
function nombreDelMes(mes) {
    if (!mesValido(mes)) return String(mes);
    const [anio, numero] = mes.split('-').map(Number);
    return `${NOMBRES_MES[numero - 1]} ${anio}`;
}

// El INDEC publica la inflación con un decimal (2,9 %): se usa así, igual que en la planilla.
function redondearIPC(fraccion) {
    return Math.round(fraccion * 1000) / 1000;
}

// ipc: { 'AAAA-MM': 0.029, ... } (fracciones, no porcentajes).
// Devuelve el factor que lleva un valor de mesBase a mesObjetivo y los meses de ese tramo
// para los que todavía no hay dato de inflación (esos meses no suman nada).
function factorIPC(mesBase, mesObjetivo, ipc) {
    let factor = 1;
    const faltantes = [];
    for (const mes of mesesEntre(mesBase, mesObjetivo)) {
        const variacion = ipc ? ipc[mes] : undefined;
        if (typeof variacion === 'number' && Number.isFinite(variacion)) factor *= 1 + redondearIPC(variacion);
        else faltantes.push(mes);
    }
    return { factor, faltantes };
}

// Valor en pesos enteros de algo que se actualiza por inflación.
// Si indexa es false (o no hay mes base) el valor queda como está.
function valorActualizado(valorBase, mesBase, mesObjetivo, ipc, indexa = true) {
    const base = Number(valorBase);
    if (!Number.isFinite(base)) return { valor: null, factor: 1, faltantes: [] };
    if (!indexa || !mesValido(mesBase) || !mesValido(mesObjetivo)) return { valor: Math.round(base), factor: 1, faltantes: [] };
    const { factor, faltantes } = factorIPC(mesBase, mesObjetivo, ipc);
    return { valor: Math.round(base * factor), factor, faltantes };
}

// Texto para avisarle a la persona que falta inflación de algún mes.
function avisoIPCFaltante(faltantes) {
    if (!faltantes || !faltantes.length) return null;
    const meses = faltantes.map(nombreDelMes);
    const lista = meses.length === 1 ? meses[0] : `${meses.slice(0, -1).join(', ')} y ${meses[meses.length - 1]}`;
    return `Falta la inflación de ${lista}: el precio quedó sin sumar ${meses.length === 1 ? 'ese mes' : 'esos meses'}. Cargala en Precios > Inflación y actualizá el presupuesto.`;
}

module.exports = {
    mesValido, aMes, mesActual, fechaDeHoy, mesSiguiente, mesesEntre, nombreDelMes,
    redondearIPC, factorIPC, valorActualizado, avisoIPCFaltante,
};
