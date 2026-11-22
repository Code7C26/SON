// Inflación mensual (IPC nacional del INDEC). Se busca sola en la API pública de datos.gob.ar y
// además se puede cargar a mano (lo cargado a mano no lo pisa la búsqueda automática).
const { mesValido } = require('./indexacion');

// Serie "IPC. Nivel General Nacional. Base dic 2016. Mensual", como variación respecto del mes anterior.
const URL_INDEC = process.env.IPC_API_URL
    || 'https://apis.datos.gob.ar/series/api/series/?ids=148.3_INIVELNAL_DICI_M_26&format=json&limit=48&sort=desc&representation_mode=percent_change';
const ESPERA_MAXIMA_MS = 15 * 1000;
const CADA_CUANTO_MS = 12 * 60 * 60 * 1000;

// Lo último que pasó al buscar (el panel lo muestra).
const estado = { ultimaVez: null, ok: null, error: null, nuevos: 0, actualizados: 0 };

// Pide la serie y la convierte en [{ mes: 'AAAA-MM', variacion: 0.029 }, ...]. Si algo no cuadra, avisa con un error.
async function pedirIPC({ fetchFn = fetch, url = URL_INDEC } = {}) {
    let respuesta;
    try {
        respuesta = await fetchFn(url, { signal: AbortSignal.timeout(ESPERA_MAXIMA_MS), headers: { Accept: 'application/json' } });
    } catch (error) {
        throw new Error(`No se pudo conectar con el INDEC (${error.message})`);
    }
    if (!respuesta.ok) throw new Error(`El INDEC respondió con error ${respuesta.status}`);
    let cuerpo;
    try {
        cuerpo = await respuesta.json();
    } catch {
        throw new Error('La respuesta del INDEC no se pudo leer');
    }
    if (!cuerpo || !Array.isArray(cuerpo.data)) throw new Error('La respuesta del INDEC no tiene el formato esperado');
    const meses = [];
    for (const fila of cuerpo.data) {
        if (!Array.isArray(fila) || typeof fila[0] !== 'string' || typeof fila[1] !== 'number' || !Number.isFinite(fila[1])) continue;
        const mes = fila[0].slice(0, 7);
        // Una variación mensual mayor al 100 % o menor al -50 % es un dato roto, no inflación.
        if (!mesValido(mes) || fila[1] > 1 || fila[1] < -0.5) continue;
        meses.push({ mes, variacion: Math.round(fila[1] * 1e6) / 1e6 });
    }
    if (!meses.length) throw new Error('El INDEC no devolvió ningún dato de inflación');
    return meses;
}

// Busca la inflación y la guarda. Devuelve { ok, nuevos, actualizados, ultimoMes } o { ok: false, error }.
async function sincronizarIPC(pool, opciones = {}) {
    estado.ultimaVez = new Date().toISOString();
    try {
        const meses = await pedirIPC(opciones);
        let nuevos = 0;
        let actualizados = 0;
        for (const { mes, variacion } of meses) {
            // Solo se escribe si el mes no existe o si lo cargó el INDEC y cambió.
            // Lo cargado a mano (fuente 'Manual') no se toca.
            const resultado = await pool.query(
                `INSERT INTO ipc_mensual (mes, variacion, fuente) VALUES ($1, $2, 'INDEC')
                 ON CONFLICT (mes) DO UPDATE SET variacion = EXCLUDED.variacion, actualizada_en = now()
                 WHERE ipc_mensual.fuente = 'INDEC' AND ipc_mensual.variacion IS DISTINCT FROM EXCLUDED.variacion
                 RETURNING (xmax = 0) AS nuevo`,
                [mes, variacion]
            );
            if (resultado.rows[0]) {
                if (resultado.rows[0].nuevo) nuevos++;
                else actualizados++;
            }
        }
        const ultimoMes = meses.map((m) => m.mes).sort().pop();
        Object.assign(estado, { ok: true, error: null, nuevos, actualizados });
        return { ok: true, nuevos, actualizados, ultimoMes };
    } catch (error) {
        Object.assign(estado, { ok: false, error: error.message, nuevos: 0, actualizados: 0 });
        return { ok: false, error: error.message };
    }
}

// { 'AAAA-MM': 0.029, ... } con todo lo que hay cargado.
async function leerIPC(pool) {
    const resultado = await pool.query('SELECT mes, variacion FROM ipc_mensual');
    const mapa = {};
    for (const fila of resultado.rows) mapa[fila.mes] = Number(fila.variacion);
    return mapa;
}

// Al arrancar y cada 12 horas. Si no hay internet no pasa nada: se sigue con lo que ya está cargado.
function programarSincronizacionIPC(pool, { cadaMs = CADA_CUANTO_MS, primeraVezMs = 5000 } = {}) {
    const buscar = async () => {
        const resultado = await sincronizarIPC(pool);
        if (!resultado.ok) console.warn(`Inflación (INDEC): ${resultado.error}`);
        else if (resultado.nuevos || resultado.actualizados) console.log(`Inflación (INDEC): ${resultado.nuevos} meses nuevos, ${resultado.actualizados} actualizados`);
    };
    const primera = setTimeout(() => buscar().catch((error) => console.error('Inflación:', error.message)), primeraVezMs);
    const repetida = setInterval(() => buscar().catch((error) => console.error('Inflación:', error.message)), cadaMs);
    primera.unref();
    repetida.unref();
}

module.exports = { URL_INDEC, estado: () => ({ ...estado }), pedirIPC, sincronizarIPC, leerIPC, programarSincronizacionIPC };
