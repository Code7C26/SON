// Ordena las visitas de un técnico en un día para que el viaje sea el más corto.
// Sale desde la base de la empresa, en Alta Gracia: así no manda primero a Córdoba
// y después hace volver. Si una dirección no está en el mapa, la busca cerca de la base.

const BASE = 'San Juan Bosco 486, Alta Gracia, Córdoba';

function normalizarDireccion(direccion) {
    return String(direccion || '').replace(/\s+/g, ' ').trim().toLowerCase();
}

function enArgentina(lat, lng) {
    return lat >= -56 && lat <= -21 && lng >= -74 && lng <= -53;
}

function distancia(a, b) {
    const rad = Math.PI / 180;
    const dLat = (b.lat - a.lat) * rad;
    const dLng = (b.lng - a.lng) * rad;
    const x = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
    return 6371 * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

function sinAcentos(texto) {
    return String(texto || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}

function parecidas(a, b) {
    const s = sinAcentos(a);
    const t = sinAcentos(b);
    const fila = Array.from({ length: t.length + 1 }, (_, i) => i);
    for (let i = 1; i <= s.length; i++) {
        let previo = i;
        for (let j = 1; j <= t.length; j++) {
            const costo = s[i - 1] === t[j - 1] ? fila[j - 1] : 1 + Math.min(fila[j - 1], fila[j], previo);
            fila[j - 1] = previo;
            previo = costo;
        }
        fila[t.length] = previo;
    }
    return fila[t.length];
}

// De una lista de lugares, el que más se parece a lo escrito y queda más cerca de la base.
function elegirLugar(consulta, base, lugares) {
    const palabras = sinAcentos(consulta).split(/\s+/).filter((palabra) => palabra.length >= 5);
    const candidatos = [];
    for (const lugar of lugares || []) {
        const lat = Number(lugar.lat);
        const lng = Number(lugar.lng);
        if (!enArgentina(lat, lng)) continue;
        const nombre = sinAcentos(`${lugar.nombre || ''} ${lugar.calle || ''}`).split(/\s+/);
        const parece = palabras.some((palabra) => nombre.some((otra) => {
            const limite = palabra.length >= 6 ? 2 : 1;
            return Math.abs(palabra.length - otra.length) <= limite && parecidas(palabra, otra) <= limite;
        }));
        if (!parece) continue;
        candidatos.push({ lat, lng, cordoba: /cordoba/.test(sinAcentos(lugar.provincia)), distancia: base ? distancia(base, { lat, lng }) : 0 });
    }
    const enCordoba = candidatos.filter((lugar) => lugar.cordoba);
    const lista = enCordoba.length ? enCordoba : candidatos;
    lista.sort((a, b) => a.distancia - b.distancia);
    return lista[0] ? { lat: lista[0].lat, lng: lista[0].lng } : null;
}

// Sale desde la base y en cada paso elige la visita más cercana.
function mejorDesdeSalida(salida, puntos) {
    if (!puntos.length) return [];
    if (!salida) return mejorRecorrido(puntos);
    const pendientes = puntos.map((punto) => ({ ...punto }));
    const camino = [];
    let actual = salida;
    while (pendientes.length) {
        let elegido = 0;
        let cerca = distancia(actual, pendientes[0]);
        for (let i = 1; i < pendientes.length; i++) {
            const valor = distancia(actual, pendientes[i]);
            if (valor < cerca) {
                cerca = valor;
                elegido = i;
            }
        }
        actual = pendientes.splice(elegido, 1)[0];
        camino.push(actual);
    }
    return camino.map((punto) => punto.id);
}

// Prueba cada visita como salida y se queda con el recorrido más corto. Sirve hasta unas 12 paradas.
function mejorRecorrido(puntos) {
    if (puntos.length <= 1) return puntos.map((punto) => punto.id);
    let mejor = null;
    let mejorCosto = Infinity;
    for (const inicio of puntos) {
        const pendientes = puntos.filter((punto) => punto.id !== inicio.id);
        const camino = [inicio];
        let costo = 0;
        let actual = inicio;
        while (pendientes.length) {
            let elegido = 0;
            let cerca = distancia(actual, pendientes[0]);
            for (let i = 1; i < pendientes.length; i++) {
                const valor = distancia(actual, pendientes[i]);
                if (valor < cerca) {
                    cerca = valor;
                    elegido = i;
                }
            }
            costo += cerca;
            actual = pendientes.splice(elegido, 1)[0];
            camino.push(actual);
        }
        if (costo < mejorCosto) {
            mejorCosto = costo;
            mejor = camino;
        }
    }
    return mejor.map((punto) => punto.id);
}

function ordenDesdeViaje(ids, waypoints) {
    if (!Array.isArray(waypoints) || waypoints.length !== ids.length) return null;
    const puestos = waypoints.map((punto, indice) => ({ id: ids[indice], puesto: punto && punto.waypoint_index }));
    if (puestos.some((punto) => !Number.isInteger(punto.puesto))) return null;
    puestos.sort((a, b) => a.puesto - b.puesto);
    return puestos.map((punto) => punto.id);
}

function dormir(ms) {
    return new Promise((resolver) => setTimeout(resolver, ms));
}

async function nominatim(direccion) {
    const consulta = /argentina/i.test(direccion) ? direccion : `${direccion}, Argentina`;
    const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&countrycodes=ar&q=${encodeURIComponent(consulta)}`;
    const respuesta = await fetch(url, {
        headers: { 'User-Agent': 'SON/1.0 (visitas de higiene y seguridad; https://sonoperation.com)', 'Accept-Language': 'es' },
        signal: AbortSignal.timeout(8000),
    });
    if (!respuesta.ok) return null;
    const lista = await respuesta.json();
    const primero = lista && lista[0];
    if (!primero) return null;
    const lat = Number(primero.lat);
    const lng = Number(primero.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || !enArgentina(lat, lng)) return null;
    return { lat, lng };
}

async function photon(direccion, base) {
    const cerca = base ? `&lat=${base.lat}&lon=${base.lng}` : '';
    const url = `https://photon.komoot.io/api/?limit=5${cerca}&q=${encodeURIComponent(direccion)}`;
    const respuesta = await fetch(url, {
        headers: { 'User-Agent': 'SON/1.0 (visitas de higiene y seguridad; https://sonoperation.com)' },
        signal: AbortSignal.timeout(8000),
    });
    if (!respuesta.ok) return null;
    const datos = await respuesta.json();
    const lugares = (datos.features || []).map((lugar) => ({
        lng: lugar.geometry && lugar.geometry.coordinates && lugar.geometry.coordinates[0],
        lat: lugar.geometry && lugar.geometry.coordinates && lugar.geometry.coordinates[1],
        nombre: lugar.properties && lugar.properties.name,
        calle: lugar.properties && lugar.properties.street,
        provincia: lugar.properties && (lugar.properties.state || lugar.properties.county),
    }));
    return elegirLugar(direccion, base, lugares);
}

async function buscarEnMapa(direccion, base) {
    const directo = await nominatim(direccion);
    if (directo) return directo;
    await dormir(1100);
    const enLaCiudad = await nominatim(`${direccion}, Alta Gracia, Córdoba`);
    if (enLaCiudad) return enLaCiudad;
    try {
        return await photon(direccion, base);
    } catch (error) {
        console.error('Mapa:', error.message);
        return null;
    }
}

async function ubicar(pool, direccion, base) {
    const clave = normalizarDireccion(direccion);
    if (clave.length < 4) return null;
    const guardada = await pool.query('SELECT lat, lng, actualizado_en FROM geocodigos WHERE direccion = $1', [clave]);
    if (guardada.rows[0]) {
        const fila = guardada.rows[0];
        const fresca = Date.now() - new Date(fila.actualizado_en).getTime() < 30 * 24 * 60 * 60 * 1000;
        if (fresca) return fila.lat == null ? null : { lat: Number(fila.lat), lng: Number(fila.lng) };
    }
    let punto = null;
    try {
        punto = await buscarEnMapa(direccion, base);
    } catch (error) {
        console.error('Mapa:', error.message);
    }
    if (punto) {
        await pool.query(
            `INSERT INTO geocodigos (direccion, lat, lng, actualizado_en) VALUES ($1, $2, $3, now())
             ON CONFLICT (direccion) DO UPDATE SET lat = EXCLUDED.lat, lng = EXCLUDED.lng, actualizado_en = now()`,
            [clave, punto.lat, punto.lng]
        );
    }
    await dormir(1100);
    return punto;
}

async function ordenPorCalles(puntos, salida) {
    if (puntos.length < 2 && !salida) return null;
    if (!puntos.length) return [];
    const coords = [...(salida ? [`${salida.lng},${salida.lat}`] : []), ...puntos.map((punto) => `${punto.lng},${punto.lat}`)].join(';');
    const url = `https://router.project-osrm.org/trip/v1/driving/${coords}?roundtrip=false&source=${salida ? 'first' : 'any'}&destination=any&overview=false`;
    try {
        const respuesta = await fetch(url, { signal: AbortSignal.timeout(8000) });
        if (!respuesta.ok) return null;
        const datos = await respuesta.json();
        if (!datos || datos.code !== 'Ok') return null;
        const marcas = salida ? datos.waypoints.slice(1) : datos.waypoints;
        return ordenDesdeViaje(puntos.map((punto) => punto.id), marcas);
    } catch (error) {
        console.error('Recorrido:', error.message);
        return null;
    }
}

// Desde dónde arranca el técnico: la ubicación que mandó el celular (si se pasa), si no la dirección
// de salida cargada en su perfil (cada uno sale de su casa: Alta Gracia, Villa María...), y si no la base.
async function puntoDeSalida(pool, tecnicoId, desde) {
    if (desde && Number.isFinite(Number(desde.lat)) && Number.isFinite(Number(desde.lng))) {
        return { lat: Number(desde.lat), lng: Number(desde.lng) };
    }
    const perfil = await pool.query('SELECT salida_direccion FROM tecnicos WHERE id = $1', [tecnicoId]);
    const direccion = perfil.rows[0] && String(perfil.rows[0].salida_direccion || '').trim();
    if (direccion) {
        const base = await ubicar(pool, BASE);
        const propia = await ubicar(pool, direccion, base);
        if (propia) return propia;
    }
    return ubicar(pool, BASE);
}

// Ordena las visitas pendientes de un día. "desde" es opcional: { lat, lng } de donde está el técnico ahora.
async function ordenarRecorrido(pool, tecnicoId, fecha, desde = null) {
    const dia = typeof fecha === 'string' ? fecha.slice(0, 10) : null;
    const id = Number(tecnicoId);
    if (!Number.isInteger(id) || !/^\d{4}-\d{2}-\d{2}$/.test(dia || '')) return;
    try {
        const ordenes = await pool.query(
            `SELECT id, direccion_trabajo FROM ordenes
             WHERE tecnico_id = $1 AND fecha_asignada = $2::date AND estado <> 'Completada'
             ORDER BY id`,
            [id, dia]
        );
        const salida = await puntoDeSalida(pool, id, desde);
        const ubicadas = [];
        for (const orden of ordenes.rows) {
            const punto = await ubicar(pool, orden.direccion_trabajo, salida);
            if (punto) {
                ubicadas.push({ id: orden.id, ...punto });
                await pool.query('UPDATE ordenes SET lat = $1, lng = $2 WHERE id = $3', [punto.lat, punto.lng, orden.id]);
            } else {
                await pool.query('UPDATE ordenes SET lat = NULL, lng = NULL, orden_ruta = NULL WHERE id = $1', [orden.id]);
            }
        }
        const ids = (await ordenPorCalles(ubicadas, salida)) || mejorDesdeSalida(salida, ubicadas);
        for (let i = 0; i < ids.length; i++) {
            await pool.query('UPDATE ordenes SET orden_ruta = $1 WHERE id = $2', [i + 1, ids[i]]);
        }
    } catch (error) {
        console.error('No se pudo ordenar la recorrida:', error.message);
    }
}

// Ordenar un recorrido tarda unos segundos (busca las direcciones en el mapa). Para no hacer esperar
// al que guarda la orden, se anota y se hace en segundo plano, de a uno y sin repetir el mismo día.
const recorridosPendientes = new Map(); // "tecnico|dia" -> { pool, tecnicoId, fecha }
let ordenandoEnFondo = false;

async function vaciarCola() {
    if (ordenandoEnFondo) return;
    ordenandoEnFondo = true;
    try {
        while (recorridosPendientes.size) {
            const [clave, tarea] = recorridosPendientes.entries().next().value;
            recorridosPendientes.delete(clave);
            await ordenarRecorrido(tarea.pool, tarea.tecnicoId, tarea.fecha);
        }
    } finally {
        ordenandoEnFondo = false;
    }
}

function programarRecorrido(pool, tecnicoId, fecha) {
    const dia = typeof fecha === 'string' ? fecha.slice(0, 10) : null;
    const id = Number(tecnicoId);
    if (!Number.isInteger(id) || !/^\d{4}-\d{2}-\d{2}$/.test(dia || '')) return;
    recorridosPendientes.set(`${id}|${dia}`, { pool, tecnicoId: id, fecha: dia });
    setImmediate(() => vaciarCola().catch((error) => console.error('Recorrido en segundo plano:', error.message)));
}

module.exports = { normalizarDireccion, mejorRecorrido, mejorDesdeSalida, elegirLugar, ordenDesdeViaje, ordenarRecorrido, programarRecorrido };
