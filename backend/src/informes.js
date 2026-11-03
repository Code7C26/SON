const fs = require('fs');
const path = require('path');

// Carpeta de red con una subcarpeta por cliente (el .env define INFORMES_DIR).
function resolverDirectorio() {
    return process.env.INFORMES_DIR || 'K:\\SIMA_Informes';
}

// Los informes se generan SIEMPRE primero en este equipo ("pendientes") y de ahí se copian a la
// carpeta de clientes. Si el servidor de archivos está apagado o sin red, el informe no se pierde:
// espera acá y se copia solo cuando vuelve. Una vez copiado, queda una copia en "enviados".
const RUTA_STORAGE = process.env.STORAGE_DIR || path.join(__dirname, '..', 'storage');
const RUTA_PENDIENTES = path.join(RUTA_STORAGE, 'pendientes');
const RUTA_ENVIADOS = path.join(RUTA_STORAGE, 'enviados');

function prepararAlmacenLocal() {
    fs.mkdirSync(RUTA_PENDIENTES, { recursive: true });
    fs.mkdirSync(RUTA_ENVIADOS, { recursive: true });
}

function normalizarNombre(nombre) {
    return String(nombre || '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toUpperCase()
        .replace(/[_]+/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

function dentroDe(raiz, destino) {
    const relativo = path.relative(raiz, destino);
    return relativo !== '' && !relativo.startsWith('..') && !path.isAbsolute(relativo);
}

function carpetaSegura(base, nombre) {
    const limpio = String(nombre || '').replace(/[\\/]/g, '').replace(/\.\./g, '').trim();
    if (!limpio) return null;
    const raiz = path.resolve(base);
    const destino = path.resolve(raiz, limpio);
    if (!dentroDe(raiz, destino)) return null;
    return destino;
}

function buscarCarpetaCliente(base, cliente) {
    const objetivo = normalizarNombre(cliente);
    if (!objetivo || !fs.existsSync(base)) return null;
    const carpetas = fs.readdirSync(base, { withFileTypes: true }).filter((entrada) => entrada.isDirectory());
    const exacta = carpetas.find((entrada) => normalizarNombre(entrada.name) === objetivo);
    if (exacta) return carpetaSegura(base, exacta.name);
    return null;
}

function archivoSeguro(base, carpeta, archivo) {
    const dir = carpetaSegura(base, carpeta);
    if (!dir) return null;
    const nombre = path.basename(String(archivo || ''));
    if (!nombre.toLowerCase().endsWith('.pdf')) return null;
    const destino = path.resolve(dir, nombre);
    if (!destino.startsWith(path.resolve(dir))) return null;
    return destino;
}

// Una carpeta de red apagada puede tardar mucho en responder: se espera un máximo y se sigue.
// Si un acceso queda colgado no se lanza otro encima (cada uno ocuparía un hilo del servidor).
const accesosColgados = new Set();

async function carpetaDisponible(ruta) {
    if (accesosColgados.has(ruta)) return false;
    const acceso = fs.promises.access(ruta).then(() => true, () => false);
    let temporizador;
    const limite = new Promise((resolver) => {
        temporizador = setTimeout(() => resolver(null), 4000);
    });
    const resultado = await Promise.race([acceso, limite]);
    clearTimeout(temporizador);
    if (resultado === null) {
        accesosColgados.add(ruta);
        acceso.finally(() => accesosColgados.delete(ruta));
        return false;
    }
    return resultado;
}

function listarPendientes() {
    const resultado = [];
    if (!fs.existsSync(RUTA_PENDIENTES)) return resultado;
    for (const carpeta of fs.readdirSync(RUTA_PENDIENTES, { withFileTypes: true })) {
        if (!carpeta.isDirectory()) continue;
        const dir = path.join(RUTA_PENDIENTES, carpeta.name);
        for (const archivo of fs.readdirSync(dir)) {
            if (archivo.toLowerCase().endsWith('.pdf')) {
                resultado.push({ carpeta: carpeta.name, archivo, ruta: path.join(dir, archivo) });
            }
        }
    }
    return resultado;
}

// Todos los informes guardados en este equipo (esperando y ya entregados), agrupados por cliente.
// Se usa cuando el servidor no puede leer la carpeta de clientes (modo "agente").
function catalogoLocal() {
    const grupos = new Map();
    const agregar = (base, entregado) => {
        if (!fs.existsSync(base)) return;
        for (const carpeta of fs.readdirSync(base, { withFileTypes: true })) {
            if (!carpeta.isDirectory()) continue;
            const clave = normalizarNombre(carpeta.name);
            if (!clave) continue;
            const grupo = grupos.get(clave) || { empresa: carpeta.name.replace(/_/g, ' '), clave, archivos: [] };
            const dir = path.join(base, carpeta.name);
            for (const archivo of fs.readdirSync(dir)) {
                if (archivo.toLowerCase().endsWith('.pdf')) {
                    grupo.archivos.push({ nombre: archivo, ruta: path.join(dir, archivo), entregado });
                }
            }
            grupos.set(clave, grupo);
        }
    };
    agregar(RUTA_ENVIADOS, true);
    agregar(RUTA_PENDIENTES, false);
    return grupos;
}

// El agente confirma que ya guardó el informe en la carpeta del cliente: pasa a "enviados".
async function confirmarEntrega(carpeta, archivo) {
    const origen = archivoSeguro(RUTA_PENDIENTES, carpeta, archivo);
    if (!origen) return false;
    const dirEnviados = carpetaSegura(RUTA_ENVIADOS, carpeta);
    if (!dirEnviados) return false;
    await fs.promises.mkdir(dirEnviados, { recursive: true });
    const destino = path.join(dirEnviados, path.basename(origen));
    if (!fs.existsSync(origen)) return fs.existsSync(destino);
    await fs.promises.rename(origen, destino);
    return true;
}

let entregando = false;

// Copia a la carpeta de clientes los informes que estaban esperando. Si la carpeta de red no
// está disponible no hace nada y lo vuelve a intentar en la próxima vuelta.
async function entregarPendientes(base) {
    if (entregando) return 0;
    entregando = true;
    let entregados = 0;
    try {
        const pendientes = listarPendientes();
        if (pendientes.length === 0) return 0;
        if (!(await carpetaDisponible(base))) return 0;

        for (const pendiente of pendientes) {
            try {
                let dirCliente = buscarCarpetaCliente(base, pendiente.carpeta);
                if (!dirCliente) {
                    dirCliente = carpetaSegura(base, pendiente.carpeta);
                    if (!dirCliente) continue;
                    await fs.promises.mkdir(dirCliente, { recursive: true });
                }
                const destino = path.join(dirCliente, pendiente.archivo);
                if (!fs.existsSync(destino)) {
                    // Se copia con un nombre temporal y se renombra al final, para que nadie
                    // vea nunca un PDF a medio copiar.
                    const parcial = `${destino}.parcial`;
                    await fs.promises.copyFile(pendiente.ruta, parcial);
                    const [original, copia] = await Promise.all([fs.promises.stat(pendiente.ruta), fs.promises.stat(parcial)]);
                    if (original.size !== copia.size) {
                        await fs.promises.unlink(parcial);
                        throw new Error('la copia quedó incompleta');
                    }
                    await fs.promises.rename(parcial, destino);
                }
                const dirEnviados = path.join(RUTA_ENVIADOS, pendiente.carpeta);
                await fs.promises.mkdir(dirEnviados, { recursive: true });
                await fs.promises.rename(pendiente.ruta, path.join(dirEnviados, pendiente.archivo));
                entregados++;
            } catch (error) {
                console.error(`No se pudo copiar ${pendiente.archivo} a la carpeta de clientes:`, error.message);
            }
        }
        if (entregados) console.log(`Informes copiados a la carpeta de clientes: ${entregados}`);
    } finally {
        entregando = false;
    }
    return entregados;
}

module.exports = {
    resolverDirectorio,
    carpetaSegura,
    archivoSeguro,
    buscarCarpetaCliente,
    carpetaDisponible,
    prepararAlmacenLocal,
    listarPendientes,
    entregarPendientes,
    catalogoLocal,
    confirmarEntrega,
    normalizarNombre,
    RUTA_PENDIENTES,
    RUTA_ENVIADOS,
};
