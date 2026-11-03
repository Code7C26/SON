// El servidor en la nube no ve el disco de la empresa. El agente le cuenta qué carpetas y PDFs hay
// ("catálogo") y, cuando alguien abre un PDF que solo está en el disco, el servidor se lo pide al
// agente y espera a que lo suba.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const RUTA_STORAGE = process.env.STORAGE_DIR || path.join(__dirname, '..', 'storage');
const RUTA_CATALOGO = path.join(RUTA_STORAGE, 'catalogo-agente.json');
const RUTA_CACHE = path.join(RUTA_STORAGE, 'cache-agente');

const MAX_CARPETAS = 5000;
const MAX_ARCHIVOS_POR_CARPETA = 20000;
const MAX_NOMBRE = 255;
const MAX_PDF_BYTES = 60 * 1024 * 1024;
const CACHE_MS = 15 * 60 * 1000;

function normalizar(nombre) {
    return String(nombre || '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toUpperCase()
        .replace(/[_]+/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

// --- Catálogo (lo que el agente ve en el disco de la empresa) ---
let catalogo = { actualizadoEn: null, carpetas: [] };

function cargarCatalogo() {
    try {
        const datos = JSON.parse(fs.readFileSync(RUTA_CATALOGO, 'utf8'));
        if (datos && Array.isArray(datos.carpetas)) catalogo = datos;
    } catch (_) {}
}
cargarCatalogo();

function nombreValido(texto) {
    return typeof texto === 'string' && texto.length > 0 && texto.length <= MAX_NOMBRE && !/[\\/\0]/.test(texto);
}

// Recibe lo que informa el agente. Devuelve la cantidad de carpetas guardadas, o null si es inválido.
function guardarCatalogo(carpetas) {
    if (!Array.isArray(carpetas) || carpetas.length > MAX_CARPETAS) return null;
    const limpias = [];
    for (const carpeta of carpetas) {
        if (!carpeta || !nombreValido(carpeta.nombre) || !Array.isArray(carpeta.archivos)) continue;
        const archivos = carpeta.archivos
            .filter((nombre) => nombreValido(nombre) && nombre.toLowerCase().endsWith('.pdf'))
            .slice(0, MAX_ARCHIVOS_POR_CARPETA);
        limpias.push({ nombre: carpeta.nombre, archivos });
    }
    catalogo = { actualizadoEn: new Date().toISOString(), carpetas: limpias };
    try {
        fs.mkdirSync(RUTA_STORAGE, { recursive: true });
        fs.writeFileSync(`${RUTA_CATALOGO}.tmp`, JSON.stringify(catalogo));
        fs.renameSync(`${RUTA_CATALOGO}.tmp`, RUTA_CATALOGO);
    } catch (error) {
        console.error('No se pudo guardar el catálogo del agente:', error.message);
    }
    return limpias.length;
}

function catalogoActualizadoEn() {
    return catalogo.actualizadoEn;
}

// Une las carpetas del disco de la empresa con los informes que guarda el propio servidor.
function carpetasUnidas(local) {
    const grupos = new Map();
    for (const carpeta of catalogo.carpetas) {
        const clave = normalizar(carpeta.nombre);
        if (!clave) continue;
        const grupo = grupos.get(clave) || { empresa: carpeta.nombre.replace(/_/g, ' '), carpeta: carpeta.nombre, nombres: new Set() };
        carpeta.archivos.forEach((archivo) => grupo.nombres.add(archivo));
        grupos.set(clave, grupo);
    }
    for (const [clave, grupo] of local) {
        const unido = grupos.get(clave) || { empresa: grupo.empresa, carpeta: grupo.empresa, nombres: new Set() };
        grupo.archivos.forEach((archivo) => unido.nombres.add(archivo.nombre));
        grupos.set(clave, unido);
    }
    return [...grupos.values()]
        .map((grupo) => ({ empresa: grupo.empresa, carpeta: grupo.carpeta, cantidad: grupo.nombres.size }))
        .sort((a, b) => a.empresa.localeCompare(b.empresa));
}

function carpetaDelCatalogo(clave) {
    return catalogo.carpetas.find((carpeta) => normalizar(carpeta.nombre) === clave) || null;
}

// Archivos de un cliente: los del disco de la empresa más los que el servidor todavía no entregó.
function archivosUnidos(clave, grupoLocal) {
    const archivos = new Map();
    const delDisco = carpetaDelCatalogo(clave);
    if (delDisco) delDisco.archivos.forEach((nombre) => archivos.set(nombre, { nombre }));
    if (grupoLocal) {
        for (const archivo of grupoLocal.archivos) {
            archivos.set(archivo.nombre, { nombre: archivo.nombre, entregado: archivo.entregado });
        }
    }
    return [...archivos.values()].sort((a, b) => b.nombre.localeCompare(a.nombre));
}

// ¿Está ese PDF en el catálogo? Devuelve los nombres reales para pedírselos al agente.
function buscarEnCatalogo(clave, archivo) {
    const carpeta = carpetaDelCatalogo(clave);
    const nombre = path.basename(String(archivo || ''));
    if (!carpeta || !carpeta.archivos.includes(nombre)) return null;
    return { carpeta: carpeta.nombre, archivo: nombre };
}

// --- Pedidos de PDFs al agente ---
const pedidos = new Map(); // id -> { carpeta, archivo, creadoEn, ruta, error }

function pedirArchivo(carpeta, archivo) {
    for (const [id, pedido] of pedidos) {
        if (pedido.carpeta === carpeta && pedido.archivo === archivo && !pedido.error && Date.now() - pedido.creadoEn < CACHE_MS) return id;
    }
    const id = crypto.randomBytes(12).toString('hex');
    pedidos.set(id, { carpeta, archivo, creadoEn: Date.now(), ruta: null, error: null });
    return id;
}

function pedidosPendientes() {
    return [...pedidos.entries()]
        .filter(([, pedido]) => !pedido.ruta && !pedido.error && Date.now() - pedido.creadoEn < 2 * 60 * 1000)
        .map(([id, pedido]) => ({ id, carpeta: pedido.carpeta, archivo: pedido.archivo }));
}

function recibirArchivo(id, contenido) {
    const pedido = pedidos.get(id);
    if (!pedido || pedido.ruta) return 'desconocido';
    if (!Buffer.isBuffer(contenido) || contenido.length === 0 || contenido.length > MAX_PDF_BYTES) return 'tamano';
    if (contenido.slice(0, 4).toString() !== '%PDF') return 'formato';
    fs.mkdirSync(RUTA_CACHE, { recursive: true });
    const ruta = path.join(RUTA_CACHE, `${id}.pdf`);
    fs.writeFileSync(ruta, contenido);
    pedido.ruta = ruta;
    return 'ok';
}

function fallarPedido(id, mensaje) {
    const pedido = pedidos.get(id);
    if (!pedido || pedido.ruta) return false;
    pedido.error = String(mensaje || 'El agente no pudo abrir el archivo').slice(0, 200);
    return true;
}

async function esperarArchivo(id, maxMs) {
    const limite = Date.now() + maxMs;
    while (Date.now() < limite) {
        const pedido = pedidos.get(id);
        if (!pedido) return { error: 'El pedido ya no existe' };
        if (pedido.ruta) return { ruta: pedido.ruta };
        if (pedido.error) return { error: pedido.error };
        await new Promise((resolver) => setTimeout(resolver, 400));
    }
    return { agotado: true };
}

// Borra los PDFs descargados para ver (no son los informes: esos están en el disco de la empresa).
function limpiarCache() {
    const ahora = Date.now();
    for (const [id, pedido] of pedidos) {
        if (ahora - pedido.creadoEn > CACHE_MS) {
            if (pedido.ruta) fs.rm(pedido.ruta, { force: true }, () => {});
            pedidos.delete(id);
        }
    }
}
setInterval(limpiarCache, 5 * 60 * 1000).unref();
try {
    fs.rmSync(RUTA_CACHE, { recursive: true, force: true }); // al arrancar no queda nada viejo
} catch (_) {}

module.exports = {
    guardarCatalogo,
    catalogoActualizadoEn,
    carpetasUnidas,
    archivosUnidos,
    buscarEnCatalogo,
    pedirArchivo,
    pedidosPendientes,
    recibirArchivo,
    fallarPedido,
    esperarArchivo,
};
