// Agente de SON: corre en una PC de la empresa que llega a la carpeta de clientes (sa-server).
// Cada tanto le pregunta al servidor de SON (en la nube) si hay informes nuevos, los baja y los
// guarda en la carpeta de cada cliente. Solo hace conexiones SALIENTES por HTTPS: no hace falta
// abrir puertos, VPN ni tocar el router.
//
// Primera vez (doble clic en SON-Agente.exe): pide el código de conexión que muestra el panel
// y la carpeta de clientes. Después queda guardado y arranca solo con Windows.
//
// Opciones para instalar sin preguntas (por ejemplo, desde un script de IT):
//   SON-Agente.exe --codigo=ABCD-EFGH@son.midominio.com --carpeta="K:\CLIENTES"
//   SON-Agente.exe --reconfigurar      (volver a vincular o cambiar la carpeta)
//
// Forma antigua (todavía válida): variables SON_URL, AGENTE_TOKEN, CARPETA_CLIENTES
// o un archivo ".env" al lado del programa.
const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const readline = require('readline');
const crypto = require('crypto');
const { spawn, spawnSync } = require('child_process');

// Archivo ".env" junto al programa (opcional): se lee antes de calcular los tiempos de abajo.
cargarEnv(path.join(path.dirname(empaquetado() ? process.execPath : __filename), '.env'));

const CADA_MS = Number(process.env.AGENTE_CADA_MS) || 30 * 1000;
const CATALOGO_CADA_MS = Number(process.env.AGENTE_CATALOGO_CADA_MS) || 3 * 60 * 1000;
const PEDIDOS_CADA_MS = Number(process.env.AGENTE_PEDIDOS_CADA_MS) || 4 * 1000;
const ACTUALIZAR_CADA_MS = Number(process.env.AGENTE_ACTUALIZAR_CADA_MS) || 30 * 60 * 1000;
const PRIMERA_ACTUALIZACION_MS = Number(process.env.AGENTE_PRIMERA_ACTUALIZACION_MS) || 2 * 60 * 1000;
function empaquetado() {
    try {
        return require('node:sea').isSea();
    } catch (_) {
        return false;
    }
}

// --- Argumentos y configuración ---
function leerArgumentos() {
    const argumentos = {};
    for (const texto of process.argv.slice(2)) {
        if (!texto.startsWith('--')) continue;
        const indice = texto.indexOf('=');
        if (indice === -1) argumentos[texto.slice(2)] = true;
        else argumentos[texto.slice(2, indice)] = texto.slice(indice + 1);
    }
    return argumentos;
}
const ARGS = leerArgumentos();
const PUERTO_UNICO = Number(ARGS.puerto) || Number(process.env.SON_AGENTE_PUERTO) || 47635;

// --- Modo servidor: instalado en una máquina que queda prendida (por ejemplo el servidor de archivos).
// Arranca solo al prender la máquina (tarea programada de Windows), aunque nadie inicie sesión.
const DIR_PROGRAMA = process.env.SON_AGENTE_DIR_PROGRAMA || path.join(process.env.ProgramFiles || 'C:\\Program Files', 'SON-Agente');
const NOMBRE_TAREA = process.env.SON_AGENTE_TAREA || 'SON-Agente';
const MODO_PRUEBA_TAREA = Boolean(process.env.SON_AGENTE_PRUEBA_TAREA); // solo para los tests: tarea del usuario, sin administrador
const MODO_SERVIDOR = Boolean(
    ARGS['modo-servidor'] || ARGS['instalar-servidor'] ||
    (empaquetado() && path.dirname(process.execPath).toLowerCase() === DIR_PROGRAMA.toLowerCase())
);

function carpetaConfigServidor() {
    return path.join(process.env.ProgramData || 'C:\\ProgramData', 'SON-Agente');
}

function carpetaConfig() {
    if (typeof ARGS.config === 'string') return ARGS.config;
    if (process.env.SON_AGENTE_CONFIG) return process.env.SON_AGENTE_CONFIG;
    if (MODO_SERVIDOR) return carpetaConfigServidor();
    if (process.env.APPDATA) return path.join(process.env.APPDATA, 'SON-Agente');
    return path.join(os.homedir(), '.son-agente');
}
const RUTA_CONFIG = path.join(carpetaConfig(), 'config.json');
const RUTA_LOG = path.join(carpetaConfig(), 'agente.log');

function cargarEnv(ruta) {
    if (!fs.existsSync(ruta)) return;
    for (const linea of fs.readFileSync(ruta, 'utf8').split(/\r?\n/)) {
        const limpia = linea.trim();
        if (!limpia || limpia.startsWith('#') || !limpia.includes('=')) continue;
        const indice = limpia.indexOf('=');
        const clave = limpia.slice(0, indice).trim();
        let valor = limpia.slice(indice + 1).trim();
        if ((valor.startsWith('"') && valor.endsWith('"')) || (valor.startsWith("'") && valor.endsWith("'"))) valor = valor.slice(1, -1);
        if (!(clave in process.env)) process.env[clave] = valor;
    }
}
function leerConfig() {
    try {
        const datos = JSON.parse(fs.readFileSync(RUTA_CONFIG, 'utf8'));
        if (datos.url && datos.token && datos.carpeta) return datos;
    } catch (_) {}
    return null;
}

function guardarConfig(config) {
    fs.mkdirSync(path.dirname(RUTA_CONFIG), { recursive: true });
    fs.writeFileSync(RUTA_CONFIG, JSON.stringify(config, null, 2));
}

// --- Registro (pantalla + archivo, porque la ventana queda minimizada) ---
function log(texto) {
    const linea = `[${new Date().toLocaleString('es-AR')}] ${texto}`;
    console.log(linea);
    try {
        fs.mkdirSync(path.dirname(RUTA_LOG), { recursive: true });
        if (fs.existsSync(RUTA_LOG) && fs.statSync(RUTA_LOG).size > 1024 * 1024) {
            fs.renameSync(RUTA_LOG, `${RUTA_LOG}.1`);
        }
        fs.appendFileSync(RUTA_LOG, linea + '\n');
    } catch (_) {}
}

// --- Interacción con la persona que instala ---
const interactivo = process.stdin.isTTY && process.stdout.isTTY;

function preguntar(texto) {
    return new Promise((resolver) => {
        const lector = readline.createInterface({ input: process.stdin, output: process.stdout });
        lector.question(texto, (respuesta) => {
            lector.close();
            resolver(respuesta.trim());
        });
    });
}

async function terminarConMensaje(texto) {
    console.error('\n' + texto);
    if (interactivo) await preguntar('\nPresioná Enter para cerrar...');
    process.exit(1);
}

// --- Utilidades de carpetas ---
function normalizarNombre(nombre) {
    return String(nombre || '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toUpperCase()
        .replace(/[_]+/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

function carpetaSegura(base, nombre) {
    const limpio = String(nombre || '').replace(/[\\/]/g, '').replace(/\.\./g, '').trim();
    if (!limpio) return null;
    const raiz = path.resolve(base);
    const destino = path.resolve(raiz, limpio);
    const relativo = path.relative(raiz, destino);
    if (relativo === '' || relativo.startsWith('..') || path.isAbsolute(relativo)) return null;
    return destino;
}

// Usa la carpeta que ya existe para ese cliente (sin importar mayúsculas, tildes o guiones bajos).
function buscarCarpetaCliente(base, cliente) {
    const objetivo = normalizarNombre(cliente);
    if (!objetivo) return null;
    const carpetas = fs.readdirSync(base, { withFileTypes: true }).filter((entrada) => entrada.isDirectory());
    const exacta = carpetas.find((entrada) => normalizarNombre(entrada.name) === objetivo);
    return exacta ? carpetaSegura(base, exacta.name) : null;
}

// Una carpeta de red apagada puede tardar mucho en responder: se espera un máximo.
let accesoColgado = false;
async function carpetaDisponible(ruta) {
    if (accesoColgado) return false;
    const acceso = fs.promises.access(ruta).then(() => true, () => false);
    let temporizador;
    const limite = new Promise((resolver) => { temporizador = setTimeout(() => resolver(null), 5000); });
    const resultado = await Promise.race([acceso, limite]);
    clearTimeout(temporizador);
    if (resultado === null) {
        accesoColgado = true;
        acceso.finally(() => { accesoColgado = false; });
        return false;
    }
    return resultado;
}

function elegirCarpetaConVentana() {
    if (process.platform !== 'win32') return null;
    const guion =
        '[Console]::OutputEncoding=[Text.Encoding]::UTF8;' +
        'Add-Type -AssemblyName System.Windows.Forms;' +
        '$d=New-Object System.Windows.Forms.FolderBrowserDialog;' +
        "$d.Description='Elegí la carpeta que contiene las carpetas de los clientes';" +
        '$d.ShowNewFolderButton=$false;' +
        "if($d.ShowDialog() -eq 'OK'){[Console]::Out.Write($d.SelectedPath)}";
    const resultado = spawnSync('powershell', ['-NoProfile', '-STA', '-Command', guion], { encoding: 'utf8' });
    const elegida = (resultado.stdout || '').trim();
    return elegida || null;
}

// --- Conexión con el servidor ---
function direccionDesde(host) {
    const limpio = host.trim().replace(/\/+$/, '');
    if (/^https?:\/\//i.test(limpio)) return limpio;
    const local = /^(localhost|127\.|10\.|192\.168\.|\d+\.\d+\.\d+\.\d+)/i.test(limpio);
    return `${local ? 'http' : 'https'}://${limpio}`;
}

function interpretarConexion(texto) {
    const limpio = String(texto || '').trim();
    const indice = limpio.lastIndexOf('@');
    if (indice <= 0 || indice === limpio.length - 1) return null;
    return { codigo: limpio.slice(0, indice).trim(), url: direccionDesde(limpio.slice(indice + 1)) };
}

async function vincular(url, codigo) {
    let respuesta;
    try {
        respuesta = await fetch(`${url}/api/agente/vincular`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ codigo, nombre: os.hostname() }),
            signal: AbortSignal.timeout(30 * 1000),
        });
    } catch (error) {
        throw new Error(`No se pudo conectar con ${url} (${error.message}). Revisá la dirección y la conexión a internet.`);
    }
    const cuerpo = await respuesta.json().catch(() => ({}));
    if (!respuesta.ok) throw new Error(cuerpo.error || `El servidor respondió ${respuesta.status}`);
    return cuerpo.token;
}

// Acceso directo en la carpeta de inicio de Windows: así el agente arranca solo al iniciar sesión.
const RUTA_ACCESO = process.env.APPDATA
    ? path.join(process.env.APPDATA, 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup', 'SON-Agente.lnk')
    : null;

async function crearInicioAutomatico() {
    if (ARGS['sin-inicio-automatico'] || process.env.SON_AGENTE_SIN_INICIO || MODO_SERVIDOR) return;
    if (!empaquetado() || process.platform !== 'win32' || !RUTA_ACCESO) return;
    const guion =
        '$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:SON_ACCESO);' +
        '$s.TargetPath=$env:SON_EXE;$s.Arguments="--inicio-automatico";$s.WorkingDirectory=Split-Path $env:SON_EXE;' +
        "$s.WindowStyle=7;$s.Description='Agente de SON';$s.Save()";
    const resultado = spawnSync('powershell', ['-NoProfile', '-Command', guion], {
        env: { ...process.env, SON_ACCESO: RUTA_ACCESO, SON_EXE: process.execPath },
        encoding: 'utf8',
    });
    if (resultado.status === 0) log('Listo: el agente va a arrancar solo cada vez que se prenda esta PC.');
    else log('No se pudo configurar el inicio automático. Hay que abrir el agente a mano cuando se prenda la PC.');
}

// --- Primera configuración ---
async function configurar() {
    console.log('==============================================');
    console.log('  Agente de SON - configuración inicial');
    console.log('==============================================\n');

    let conexion = interpretarConexion(ARGS.codigo);
    if (!conexion && ARGS.codigo) await terminarConMensaje('El código de conexión no tiene el formato correcto. Debe verse así: ABCD-EFGH@son.sudominio.com');
    if (!conexion && !interactivo) await terminarConMensaje('Falta el código de conexión. Usá --codigo=ABCD-EFGH@son.sudominio.com');

    let token;
    while (!token) {
        if (!conexion) {
            console.log('1) En el panel de SON entrá a Informes > "Conectar agente" y tocá "Generar código".');
            const texto = await preguntar('   Pegá acá el código de conexión (se ve como ABCD-EFGH@son.sudominio.com): ');
            conexion = interpretarConexion(texto);
            if (!conexion) {
                console.log('   Eso no parece un código de conexión. Probá de nuevo.\n');
                continue;
            }
        }
        try {
            token = await vincular(conexion.url, conexion.codigo);
        } catch (error) {
            console.log(`   ${error.message}\n`);
            if (!interactivo || ARGS.codigo) await terminarConMensaje('No se pudo vincular el agente.');
            conexion = null;
        }
    }
    console.log('   Vinculado correctamente con el servidor.\n');

    let carpeta = ARGS.carpeta;
    while (!carpeta || !(await carpetaDisponible(carpeta))) {
        if (carpeta) {
            console.log(`   No se puede acceder a esa carpeta: ${carpeta}`);
            if (!interactivo) await terminarConMensaje('La carpeta de clientes no está disponible.');
        }
        console.log('2) Elegí la carpeta donde están las carpetas de los clientes (la de "00. CLIENTES").');
        const escrita = await preguntar('   Escribí la ruta, o apretá Enter para elegirla en una ventana: ');
        carpeta = escrita || elegirCarpetaConVentana() || '';
        if (!carpeta) console.log('   No se eligió ninguna carpeta.\n');
    }
    console.log(`   Carpeta de clientes: ${carpeta}\n`);
    if (MODO_SERVIDOR && carpeta.startsWith('\\\\')) {
        console.log('   AVISO: es una ruta de red (\\\\...). En el servidor conviene la ruta LOCAL del disco (por ejemplo D:\\...),');
        console.log('   porque el agente trabaja como servicio del sistema y puede no tener permiso sobre la ruta de red.\n');
    }

    guardarConfig({ url: conexion.url, token, carpeta });
    log(`Agente configurado. Servidor: ${conexion.url} | Carpeta: ${carpeta}`);
    await crearInicioAutomatico();
    return { url: conexion.url, token, carpeta };
}

// --- Trabajo del agente ---
function crearAgente({ url, token, carpeta }) {
    async function pedir(ruta, opciones = {}) {
        return fetch(`${url}${ruta}`, {
            ...opciones,
            headers: { 'x-agente-token': token, ...(opciones.headers || {}) },
            signal: AbortSignal.timeout(120 * 1000),
        });
    }

    async function entregar({ carpeta: cliente, archivo, tamano }) {
        let dirCliente = buscarCarpetaCliente(carpeta, cliente);
        if (!dirCliente) {
            dirCliente = carpetaSegura(carpeta, cliente);
            if (!dirCliente) throw new Error(`nombre de cliente inválido: ${cliente}`);
            fs.mkdirSync(dirCliente, { recursive: true });
            log(`Carpeta nueva para el cliente: ${path.basename(dirCliente)}`);
        }
        const destino = path.join(dirCliente, path.basename(archivo));

        const yaEsta = fs.existsSync(destino) && fs.statSync(destino).size === tamano;
        if (!yaEsta) {
            const respuesta = await pedir(`/api/agente/descargar/${encodeURIComponent(cliente)}/${encodeURIComponent(archivo)}`);
            if (!respuesta.ok) throw new Error(`el servidor respondió ${respuesta.status} al descargar`);
            const contenido = Buffer.from(await respuesta.arrayBuffer());
            if (contenido.length !== tamano) throw new Error('la descarga llegó incompleta');
            // Se escribe con un nombre temporal y se renombra al final: nadie ve un PDF a medias.
            const parcial = `${destino}.parcial`;
            fs.writeFileSync(parcial, contenido);
            fs.renameSync(parcial, destino);
        }

        const confirmacion = await pedir('/api/agente/confirmar', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ carpeta: cliente, archivo }),
        });
        if (!confirmacion.ok) throw new Error(`el servidor no confirmó la entrega (${confirmacion.status})`);
        log(`Entregado: ${path.basename(dirCliente)} / ${archivo}`);
    }

    let ultimoAviso = '';
    function avisarUnaVez(texto) {
        if (texto !== ultimoAviso) log(texto);
        ultimoAviso = texto;
    }

    async function ciclo() {
        let lista;
        try {
            const respuesta = await pedir('/api/agente/pendientes');
            if (respuesta.status === 401) {
                return avisarUnaVez('El servidor no reconoce a este agente (lo desvincularon o cambió la clave). Ejecutá SON-Agente.exe --reconfigurar para volver a vincularlo.');
            }
            if (!respuesta.ok) return avisarUnaVez(`El servidor respondió ${respuesta.status}.`);
            lista = await respuesta.json();
        } catch (error) {
            return avisarUnaVez(`Sin conexión con el servidor de SON (${error.message}). Se reintenta solo.`);
        }
        ultimoAviso = '';
        if (lista.length === 0) return;

        if (!(await carpetaDisponible(carpeta))) {
            return avisarUnaVez(`La carpeta de clientes no está disponible (${carpeta}). Hay ${lista.length} informe(s) esperando; se reintenta solo.`);
        }
        for (const item of lista) {
            try {
                await entregar(item);
            } catch (error) {
                log(`No se pudo entregar ${item.archivo}: ${error.message}. Se reintenta.`);
            }
        }
    }

    async function bucle() {
        try {
            await ciclo();
        } catch (error) {
            log(`Error inesperado: ${error.message}`);
        }
        setTimeout(bucle, CADA_MS);
    }

    // --- Catálogo: le cuenta al servidor qué carpetas y PDFs hay en el disco de la empresa,
    // así el panel las muestra aunque el servidor esté en la nube.
    let ultimoCatalogo = '';
    let ultimoEnvioCatalogo = 0;
    let escaneando = false;

    async function leerCatalogo() {
        const entradas = await fs.promises.readdir(carpeta, { withFileTypes: true });
        const directorios = entradas.filter((entrada) => entrada.isDirectory());
        const carpetas = [];
        let indice = 0;
        async function trabajador() {
            while (indice < directorios.length) {
                const directorio = directorios[indice++];
                try {
                    const nombres = await fs.promises.readdir(path.join(carpeta, directorio.name));
                    carpetas.push({ nombre: directorio.name, archivos: nombres.filter((nombre) => nombre.toLowerCase().endsWith('.pdf')) });
                } catch (_) {}
            }
        }
        await Promise.all([trabajador(), trabajador(), trabajador(), trabajador()]);
        return carpetas.sort((a, b) => a.nombre.localeCompare(b.nombre));
    }

    async function escanearCatalogo() {
        if (escaneando) return;
        escaneando = true;
        const liberar = setTimeout(() => { escaneando = false; }, 5 * 60 * 1000); // por si el disco se cuelga
        try {
            if (!(await carpetaDisponible(carpeta))) return;
            const carpetas = await leerCatalogo();
            const huella = JSON.stringify(carpetas);
            if (huella === ultimoCatalogo && Date.now() - ultimoEnvioCatalogo < 30 * 60 * 1000) return;
            const respuesta = await pedir('/api/agente/catalogo', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ carpetas }),
            });
            if (respuesta.ok) {
                if (huella !== ultimoCatalogo) log(`Catálogo enviado al servidor: ${carpetas.length} carpeta(s) de clientes.`);
                ultimoCatalogo = huella;
                ultimoEnvioCatalogo = Date.now();
            }
        } catch (_) {
            // sin conexión o disco ocupado: se reintenta en la próxima vuelta
        } finally {
            clearTimeout(liberar);
            escaneando = false;
        }
    }

    // --- Pedidos de PDFs: cuando alguien abre en el panel un informe viejo (que solo está en el
    // disco), el servidor se lo pide al agente y el agente lo sube.
    let atendiendo = false;

    async function subirArchivo({ id, carpeta: cliente, archivo }) {
        if (!(await carpetaDisponible(carpeta))) throw new Error('El disco de la empresa no está disponible en este momento');
        const dir = carpetaSegura(carpeta, cliente);
        const nombre = path.basename(String(archivo || ''));
        if (!dir || !nombre.toLowerCase().endsWith('.pdf')) throw new Error('Pedido inválido');
        const ruta = path.join(dir, nombre);
        if (!fs.existsSync(ruta)) throw new Error('El archivo ya no está en la carpeta del cliente');
        if (fs.statSync(ruta).size > 55 * 1024 * 1024) throw new Error('El PDF pesa más de 55 MB y no se puede abrir desde el panel');
        const contenido = await fs.promises.readFile(ruta);
        const respuesta = await pedir(`/api/agente/archivo/${id}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/pdf' },
            body: contenido,
        });
        if (!respuesta.ok) throw new Error(`el servidor respondió ${respuesta.status}`);
        log(`Subido para ver en el panel: ${cliente} / ${nombre}`);
    }

    async function atenderPedidos() {
        if (atendiendo) return;
        atendiendo = true;
        try {
            const respuesta = await pedir('/api/agente/solicitudes');
            if (!respuesta.ok) return;
            for (const pedido of await respuesta.json()) {
                try {
                    await subirArchivo(pedido);
                } catch (error) {
                    log(`No se pudo subir ${pedido.archivo}: ${error.message}`);
                    await pedir(`/api/agente/archivo/${pedido.id}/error`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ mensaje: error.message }),
                    }).catch(() => {});
                }
            }
        } catch (_) {
            // sin conexión: se reintenta solo
        } finally {
            atendiendo = false;
        }
    }

    // --- Actualización automática: si el servidor tiene una versión más nueva del programa, el
    // agente la baja, la reemplaza y se reinicia solo. Nadie tiene que hacer nada.
    function huellaArchivo(ruta) {
        return new Promise((resolver, rechazar) => {
            const hash = crypto.createHash('sha256');
            fs.createReadStream(ruta).on('data', (parte) => hash.update(parte)).on('end', () => resolver(hash.digest('hex'))).on('error', rechazar);
        });
    }

    let huellaPropia = null;
    let ultimoErrorActualizacion = '';

    let reiniciando = false; // ya se actualizó: este proceso está por cerrarse, no debe volver a actualizar

    async function actualizarSiHaceFalta() {
        if (!empaquetado() || process.platform !== 'win32' || reiniciando) return;
        if (ARGS['sin-actualizacion'] || process.env.SON_AGENTE_SIN_ACTUALIZAR) return;
        try {
            try {
                fs.rmSync(`${process.execPath}.viejo`, { force: true }); // resto de una actualización anterior
            } catch (_) {} // si todavía está en uso, se borra en la próxima vuelta
            const respuesta = await pedir('/api/agente/programa/version');
            if (!respuesta.ok) return;
            const { hash, tamano } = await respuesta.json();
            if (!hash) return;
            if (!huellaPropia) huellaPropia = await huellaArchivo(process.execPath);
            if (hash === huellaPropia) return;

            log('Hay una versión nueva del agente. Descargando...');
            const descarga = await pedir('/api/agente/programa');
            if (!descarga.ok) throw new Error(`el servidor respondió ${descarga.status}`);
            const contenido = Buffer.from(await descarga.arrayBuffer());
            const huellaBajada = crypto.createHash('sha256').update(contenido).digest('hex');
            if (contenido.length !== tamano || huellaBajada !== hash || contenido.slice(0, 2).toString() !== 'MZ') {
                throw new Error('la descarga llegó dañada');
            }

            const exe = process.execPath;
            const nuevo = `${exe}.nuevo`;
            const viejo = `${exe}.viejo`;
            fs.writeFileSync(nuevo, contenido);
            fs.rmSync(viejo, { force: true });
            fs.renameSync(exe, viejo); // Windows deja renombrar un programa que está corriendo
            try {
                fs.renameSync(nuevo, exe);
            } catch (error) {
                fs.renameSync(viejo, exe);
                throw error;
            }
            reiniciando = true;
            log('Agente actualizado. Reiniciando con la versión nueva...');
            liberarCandado();
            lanzarEnSegundoPlano(['--tras-actualizar']);
            setTimeout(() => process.exit(0), 500);
        } catch (error) {
            try { fs.rmSync(`${process.execPath}.nuevo`, { force: true }); } catch (_) {} // no dejar archivos a medias
            const mensaje = `No se pudo actualizar el agente: ${error.message}. Se reintenta más tarde.`;
            if (mensaje !== ultimoErrorActualizacion) log(mensaje);
            ultimoErrorActualizacion = mensaje;
        }
    }

    log(`Agente de SON iniciado. Servidor: ${url} | Carpeta de clientes: ${carpeta} | cada ${Math.round(CADA_MS / 1000)} s`);
    bucle();
    setTimeout(() => {
        actualizarSiHaceFalta();
        setInterval(actualizarSiHaceFalta, ACTUALIZAR_CADA_MS);
    }, PRIMERA_ACTUALIZACION_MS);
    setInterval(atenderPedidos, PEDIDOS_CADA_MS);
    (function vueltaCatalogo() {
        escanearCatalogo().finally(() => setTimeout(vueltaCatalogo, CATALOGO_CADA_MS));
    })();
}

// --- Un solo agente por PC ---
let candado = null;

function unSoloAgente(reintentos = 0) {
    return new Promise((resolver) => {
        const servidor = net.createServer();
        servidor.once('error', () => {
            if (reintentos > 0) setTimeout(() => unSoloAgente(reintentos - 1).then(resolver), 500);
            else resolver(false);
        });
        servidor.listen(PUERTO_UNICO, '127.0.0.1', () => {
            candado = servidor;
            resolver(true);
        });
    });
}

function liberarCandado() {
    if (candado) candado.close();
    candado = null;
}

function agenteCorriendo() {
    return new Promise((resolver) => {
        const conexion = net.connect({ port: PUERTO_UNICO, host: '127.0.0.1' });
        conexion.setTimeout(1500, () => { conexion.destroy(); resolver(false); });
        conexion.once('connect', () => { conexion.destroy(); resolver(true); });
        conexion.once('error', () => resolver(false));
    });
}

// --- Funcionamiento en segundo plano (sin ventana) ---
function lanzarEnSegundoPlano(extra = []) {
    const heredados = [];
    if (MODO_SERVIDOR) heredados.push('--modo-servidor');
    if (typeof ARGS.config === 'string') heredados.push(`--config=${ARGS.config}`);
    if (ARGS.puerto) heredados.push(`--puerto=${ARGS.puerto}`);
    const hijo = spawn(process.execPath, ['--en-segundo-plano', ...heredados, ...extra], { detached: true, windowsHide: true, stdio: 'ignore' });
    hijo.unref();
}

// Cierra los otros agentes que estén corriendo (el que trabaja oculto), sin tocar este proceso.
// Solo cierra programas que salen de ESE mismo archivo (otra copia en otra carpeta no se toca).
function detenerOtros(rutaExe = process.execPath) {
    if (!empaquetado() || process.platform !== 'win32') return;
    const guion =
        "Get-CimInstance Win32_Process -Filter \"Name='$env:SON_NOMBRE'\" | " +
        'Where-Object { $_.ExecutablePath -eq $env:SON_EXE -and $_.ProcessId -ne [int]$env:SON_PID } | ' +
        'ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }';
    spawnSync('powershell', ['-NoProfile', '-Command', guion], {
        env: { ...process.env, SON_NOMBRE: path.basename(rutaExe), SON_EXE: rutaExe, SON_PID: String(process.pid) },
        stdio: 'ignore',
    });
}

const esperar = (ms) => new Promise((resolver) => setTimeout(resolver, ms));

async function pausaSiHayVentana(ms) {
    if (interactivo && !ARGS['inicio-automatico']) await esperar(ms);
}

// Lo que pasa al abrir SON-Agente.exe con doble clic: configura si hace falta, deja el agente
// trabajando oculto y esta ventana se cierra sola.
async function lanzarDesdeVentana() {
    const reconfigurando = ARGS.reconfigurar || ARGS.codigo;
    if (reconfigurando) {
        detenerOtros();
        await esperar(1500);
    } else if (await agenteCorriendo()) {
        console.log('El agente de SON ya está funcionando en segundo plano. No hace falta hacer nada.');
        await pausaSiHayVentana(4000);
        return process.exit(0);
    }
    let config = reconfigurando ? null : leerConfig();
    if (!config) config = await configurar();
    lanzarEnSegundoPlano();
    log('Agente iniciado en segundo plano.');
    if (!ARGS['inicio-automatico']) {
        console.log('\n==============================================');
        console.log('  Listo: el agente de SON quedó funcionando');
        console.log('  en segundo plano (sin ventana).');
        console.log('  Podés cerrar esta ventana. Arranca solo');
        console.log('  cada vez que se prende esta PC.');
        console.log('==============================================\n');
        console.log('  Ver estado:   SON-Agente.exe --estado');
        console.log('  Desinstalar:  SON-Agente.exe --desinstalar\n');
    }
    await pausaSiHayVentana(7000);
    process.exit(0);
}

async function comandoEstado() {
    const corriendo = await agenteCorriendo();
    const config = leerConfig();
    const hayTarea = tareaExiste();
    console.log(`\nAgente de SON: ${corriendo ? 'FUNCIONANDO en segundo plano' : 'DETENIDO (abrí SON-Agente.exe para iniciarlo)'}`);
    if (hayTarea) console.log(`Instalado como SERVIDOR: arranca solo al prender la máquina (tarea programada "${NOMBRE_TAREA}").`);
    if (config) console.log(`Servidor: ${config.url}\nCarpeta de clientes: ${config.carpeta}`);
    else if (hayTarea && !MODO_SERVIDOR) console.log(`La configuración del servidor se ve con: "${path.join(DIR_PROGRAMA, 'SON-Agente.exe')}" --estado (en una consola de administrador).`);
    else if (hayTarea) console.log('No se pudo leer la configuración: abrí la consola como administrador.');
    else console.log('Todavía no está configurado.');
    try {
        const lineas = fs.readFileSync(RUTA_LOG, 'utf8').trim().split(/\r?\n/).slice(-8);
        console.log(`\nÚltimos movimientos (${RUTA_LOG}):\n${lineas.join('\n')}`);
    } catch (_) {}
    await pausaSiHayVentana(15000);
}

// ======================================================================
// Instalación como SERVIDOR (arranca al prender la máquina, sin iniciar sesión)
// ======================================================================
function esAdministrador() {
    if (process.platform !== 'win32') return false;
    return spawnSync('fltmc', [], { stdio: 'ignore' }).status === 0;
}

function schtasks(...argumentos) {
    return spawnSync('schtasks', argumentos, { encoding: 'utf8' });
}

function tareaExiste() {
    return process.platform === 'win32' && schtasks('/Query', '/TN', NOMBRE_TAREA).status === 0;
}

function exeInstalado() {
    return path.join(DIR_PROGRAMA, 'SON-Agente.exe');
}

function carpetaConfigDeServidor() {
    if (typeof ARGS.config === 'string') return ARGS.config;
    return process.env.SON_AGENTE_CONFIG || carpetaConfigServidor();
}

// Definición de la tarea programada: arranca con la máquina, sin límite de tiempo, se reintenta
// si falla y cada 15 minutos revisa que siga funcionando (si ya está corriendo, no hace nada).
function xmlTarea(exe, argumentos) {
    const esc = (texto) => String(texto).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    const disparadores =
        (MODO_PRUEBA_TAREA ? '' : '<BootTrigger><Enabled>true</Enabled></BootTrigger>') +
        '<TimeTrigger><Repetition><Interval>PT15M</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>' +
        '<StartBoundary>2020-01-01T00:00:00</StartBoundary><Enabled>true</Enabled></TimeTrigger>';
    const principal = MODO_PRUEBA_TAREA
        ? `<Principal id="Author"><UserId>${esc(`${process.env.USERDOMAIN}\\${process.env.USERNAME}`)}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal>`
        : '<Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal>';
    return '<?xml version="1.0" encoding="UTF-16"?>\n' +
        '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">' +
        '<RegistrationInfo><Description>Agente de SON: entrega los informes en el disco de la empresa.</Description></RegistrationInfo>' +
        `<Triggers>${disparadores}</Triggers>` +
        `<Principals>${principal}</Principals>` +
        '<Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>' +
        '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>' +
        '<AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable>' +
        '<RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><AllowStartOnDemand>true</AllowStartOnDemand>' +
        '<Enabled>true</Enabled><Hidden>false</Hidden><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>7</Priority>' +
        '<RestartOnFailure><Interval>PT1M</Interval><Count>999</Count></RestartOnFailure></Settings>' +
        `<Actions Context="Author"><Exec><Command>${esc(exe)}</Command><Arguments>${esc(argumentos)}</Arguments>` +
        `<WorkingDirectory>${esc(path.dirname(exe))}</WorkingDirectory></Exec></Actions></Task>`;
}

// Vuelve a abrir este mismo programa con permisos de administrador (Windows pide confirmar).
async function pedirAdministrador() {
    console.log('Esto necesita permisos de administrador. Va a aparecer una ventana de Windows pidiendo confirmación: tocá "Sí".\n');
    const argumentos = process.argv.slice(2).map((texto) => `"${texto}"`).join(' ');
    const resultado = spawnSync('powershell', ['-NoProfile', '-Command', 'Start-Process -FilePath $env:SON_EXE -ArgumentList $env:SON_ARGS -Verb RunAs -Wait'], {
        env: { ...process.env, SON_EXE: process.execPath, SON_ARGS: argumentos },
        stdio: 'inherit',
    });
    if (resultado.status !== 0) {
        await terminarConMensaje('No se pudo abrir como administrador (¿se canceló la ventana de confirmación?).\nAbrí el Símbolo del sistema con clic derecho > "Ejecutar como administrador" y repetí el comando.');
    }
    process.exit(0);
}

async function comandoInstalarServidor() {
    if (!empaquetado() || process.platform !== 'win32') {
        await terminarConMensaje('La instalación como servidor funciona solo con SON-Agente.exe en Windows.');
    }
    if (!MODO_PRUEBA_TAREA && !esAdministrador()) return pedirAdministrador();

    console.log('==============================================');
    console.log('  Agente de SON - instalación en el SERVIDOR');
    console.log('==============================================\n');

    const destino = exeInstalado();
    // 1) Si ya había una versión instalada, se frena para poder reemplazarla.
    schtasks('/End', '/TN', NOMBRE_TAREA);
    detenerOtros(destino);
    await esperar(1500);

    // 2) Se copia el programa a Program Files (ahí solo escriben los administradores).
    try {
        fs.mkdirSync(DIR_PROGRAMA, { recursive: true });
        if (path.resolve(process.execPath).toLowerCase() !== path.resolve(destino).toLowerCase()) fs.copyFileSync(process.execPath, destino);
    } catch (error) {
        await terminarConMensaje(`No se pudo copiar el programa a ${DIR_PROGRAMA}: ${error.message}`);
    }
    console.log(`Programa instalado en: ${destino}\n`);

    // 3) Vinculación con el servidor de SON y carpeta de clientes.
    let config = ARGS.reconfigurar || ARGS.codigo ? null : leerConfig();
    if (config) console.log(`Ya estaba vinculado con ${config.url} (carpeta: ${config.carpeta}). Se conserva; para cambiarlo usá --reconfigurar.\n`);
    else config = await configurar();

    // 4) La configuración guarda la clave de conexión: queda legible solo para el sistema y los administradores.
    if (!MODO_PRUEBA_TAREA) {
        spawnSync('icacls', [carpetaConfig(), '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '/T'], { stdio: 'ignore' });
    }

    if (await agenteCorriendo()) {
        await terminarConMensaje('Hay otro agente de SON funcionando en esta máquina (un programa de otra carpeta u otro usuario).\nCerralo (Administrador de tareas) y volvé a ejecutar este comando.');
    }

    // 5) Tarea programada que arranca con la máquina.
    const argumentosTarea = ['--en-segundo-plano', '--modo-servidor'];
    if (typeof ARGS.config === 'string') argumentosTarea.push(`--config=${ARGS.config}`);
    if (ARGS.puerto) argumentosTarea.push(`--puerto=${ARGS.puerto}`);
    const archivoXml = path.join(os.tmpdir(), `son-tarea-${process.pid}.xml`);
    fs.writeFileSync(archivoXml, '\ufeff' + xmlTarea(destino, argumentosTarea.join(' ')), 'utf16le');
    const creada = schtasks('/Create', '/TN', NOMBRE_TAREA, '/XML', archivoXml, '/F');
    fs.rmSync(archivoXml, { force: true });
    if (creada.status !== 0) {
        await terminarConMensaje(`No se pudo crear la tarea programada de Windows:\n${(creada.stderr || creada.stdout || '').trim()}`);
    }
    log('Instalado como servidor: tarea programada creada, arranca con la máquina.');

    // 6) Se arranca ya mismo y se comprueba que haya podido leer el disco y hablar con el servidor.
    let tamanoLog = 0;
    try { tamanoLog = fs.statSync(RUTA_LOG).size; } catch (_) {}
    schtasks('/Run', '/TN', NOMBRE_TAREA);
    console.log('Arrancando el agente y comprobando que llegue a la carpeta de clientes...');
    let verificado = false;
    for (let i = 0; i < 45 && !verificado; i++) {
        await esperar(1000);
        try {
            const nuevo = fs.readFileSync(RUTA_LOG, 'utf8').slice(tamanoLog);
            verificado = nuevo.includes('Catálogo enviado') || nuevo.includes('CatÃ¡logo enviado');
        } catch (_) {}
    }
    console.log('');
    if (verificado) {
        console.log('==============================================');
        console.log('  LISTO: el agente quedó instalado en el servidor');
        console.log('  y ya está leyendo la carpeta de clientes.');
        console.log('  Arranca solo cada vez que se prende la máquina.');
        console.log('==============================================\n');
    } else {
        console.log('ATENCIÓN: el agente quedó instalado pero no pude confirmar que lea la carpeta de clientes.');
        console.log('Lo más probable es que la ruta no sea la correcta o que el sistema no tenga permiso sobre ella.');
        try {
            console.log(`\nÚltimos movimientos (${RUTA_LOG}):\n${fs.readFileSync(RUTA_LOG, 'utf8').trim().split(/\r?\n/).slice(-6).join('\n')}\n`);
        } catch (_) {}
    }
    console.log(`  Ver estado:   "${destino}" --estado`);
    console.log(`  Desinstalar:  "${destino}" --desinstalar\n`);
    if (interactivo) await preguntar('Presioná Enter para cerrar...');
    process.exit(verificado ? 0 : 1);
}

async function comandoDetenerServidor() {
    if (!MODO_PRUEBA_TAREA && !esAdministrador()) return pedirAdministrador();
    schtasks('/Change', '/TN', NOMBRE_TAREA, '/DISABLE');
    schtasks('/End', '/TN', NOMBRE_TAREA);
    detenerOtros(exeInstalado());
    console.log('Agente detenido. No va a arrancar hasta que ejecutes: SON-Agente.exe --iniciar');
    await pausaSiHayVentana(5000);
}

async function comandoIniciarServidor() {
    if (!MODO_PRUEBA_TAREA && !esAdministrador()) return pedirAdministrador();
    schtasks('/Change', '/TN', NOMBRE_TAREA, '/ENABLE');
    schtasks('/Run', '/TN', NOMBRE_TAREA);
    console.log('Agente iniciado. Comprobalo con: SON-Agente.exe --estado');
    await pausaSiHayVentana(5000);
}

async function desinstalarServidor() {
    if (!MODO_PRUEBA_TAREA && !esAdministrador()) return pedirAdministrador();
    schtasks('/End', '/TN', NOMBRE_TAREA);
    schtasks('/Delete', '/TN', NOMBRE_TAREA, '/F');
    detenerOtros(exeInstalado());
    await esperar(1000);
    fs.rmSync(carpetaConfigDeServidor(), { recursive: true, force: true });
    const corriendoDesdeAhi = path.resolve(process.execPath).toLowerCase().startsWith(path.resolve(DIR_PROGRAMA).toLowerCase() + path.sep);
    if (corriendoDesdeAhi) {
        // Este mismo programa está en esa carpeta: se borra un instante después de cerrarse.
        spawn('cmd.exe', ['/c', `ping -n 4 127.0.0.1 >nul & rmdir /s /q "${DIR_PROGRAMA}"`], { detached: true, windowsHide: true, stdio: 'ignore', windowsVerbatimArguments: true }).unref();
    } else {
        fs.rmSync(DIR_PROGRAMA, { recursive: true, force: true });
    }
    console.log('\nAgente desinstalado del servidor: se detuvo, ya no arranca con la máquina y se borró el programa y su configuración.');
    console.log('Para volver a usarlo hay que generar un código nuevo en el panel.');
    await pausaSiHayVentana(8000);
}

async function comandoDesinstalar() {
    if (tareaExiste()) return desinstalarServidor();
    detenerOtros();
    if (RUTA_ACCESO) fs.rmSync(RUTA_ACCESO, { force: true });
    fs.rmSync(RUTA_CONFIG, { force: true });
    console.log('\nAgente desinstalado: se detuvo, ya no arranca con Windows y se borró su configuración.');
    console.log('Podés borrar el archivo SON-Agente.exe. Para volver a usarlo hay que generar un código nuevo en el panel.');
    await pausaSiHayVentana(8000);
}

async function main() {
    if (ARGS['instalar-servidor']) return comandoInstalarServidor();
    if (ARGS.desinstalar) return comandoDesinstalar();
    if (ARGS.iniciar && tareaExiste()) return comandoIniciarServidor();
    if (ARGS.detener && tareaExiste()) return comandoDetenerServidor();
    if (ARGS.detener) {
        detenerOtros();
        console.log('Agente detenido. Vuelve a arrancar cuando abras SON-Agente.exe o al prender la PC.');
        return pausaSiHayVentana(5000);
    }
    if (ARGS.estado) return comandoEstado();

    const abiertoConDobleClic = empaquetado() && !ARGS['en-segundo-plano'] && !ARGS['primer-plano'] && !process.env.SON_AGENTE_PRIMER_PLANO;
    if (abiertoConDobleClic) return lanzarDesdeVentana();

    // Este es el proceso que trabaja (oculto o, en pruebas, a la vista).
    if (!(await unSoloAgente(ARGS['tras-actualizar'] ? 20 : 0))) {
        if (ARGS['en-segundo-plano']) {
            log('Ya había un agente corriendo: este se cierra.');
            process.exit(0);
        }
        await terminarConMensaje('Ya hay un agente de SON corriendo en esta PC. No hace falta abrir otro.');
    }

    let config = null;
    if (process.env.SON_URL && process.env.AGENTE_TOKEN && process.env.CARPETA_CLIENTES) {
        config = {
            url: process.env.SON_URL.trim().replace(/\/+$/, ''),
            token: process.env.AGENTE_TOKEN.trim(),
            carpeta: process.env.CARPETA_CLIENTES.trim(),
        };
    } else if (!ARGS.reconfigurar && !ARGS.codigo) {
        config = leerConfig();
    }
    if (!config && ARGS['en-segundo-plano']) {
        log('El agente no está configurado: abrí SON-Agente.exe para vincularlo.');
        process.exit(1);
    }
    if (!config) config = await configurar();
    crearAgente(config);
}

main().catch((error) => terminarConMensaje(`Error: ${error.message}`));
