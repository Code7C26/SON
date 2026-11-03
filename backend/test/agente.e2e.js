// Prueba el modo "agente": servidor en la nube + programa de la empresa que entrega los informes.
// Uso:   node test/agente.e2e.js
// Levanta su propio servidor (puerto 3003) y su propio agente con carpetas temporales
// (no toca las reales) y borra al terminar todo lo que crea.
require('dotenv').config();
const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Pool } = require('pg');

const PUERTO = 3003;
const BASE = `http://127.0.0.1:${PUERTO}`;
const TOKEN_AGENTE = 'token-de-prueba-largo-1234567890abcdef';
const RAIZ = fs.mkdtempSync(path.join(os.tmpdir(), 'son_agente_'));
const CLIENTES = path.join(RAIZ, 'clientes'); // al principio NO existe: simula sa-server apagado
const STORAGE = path.join(RAIZ, 'storage');
const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const pool = new Pool({
    user: process.env.DB_USER, host: process.env.DB_HOST, database: process.env.DB_NAME,
    password: process.env.DB_PASSWORD, port: Number(process.env.DB_PORT || 5432),
});

let fallos = 0;
function paso(nombre, ok, detalle = '') {
    if (!ok) fallos++;
    console.log(`${ok ? 'OK   ' : 'FALLA'} ${nombre}${detalle ? ' -> ' + detalle : ''}`);
}
const espera = (ms) => new Promise((resolver) => setTimeout(resolver, ms));

async function api(metodo, ruta, token, cuerpo, cabeceras = {}) {
    const res = await fetch(BASE + ruta, {
        method: metodo,
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...cabeceras },
        body: cuerpo ? JSON.stringify(cuerpo) : undefined,
    });
    const tipo = res.headers.get('content-type') || '';
    const datos = tipo.includes('json') ? await res.json() : Buffer.from(await res.arrayBuffer());
    return { status: res.status, datos };
}

function pdfsEn(dir) {
    return fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.pdf')) : [];
}

function levantarServidor() {
    return new Promise((resolver, rechazar) => {
        const proceso = spawn(process.execPath, ['index.js'], {
            cwd: path.join(__dirname, '..'),
            env: {
                ...process.env, PORT: String(PUERTO), STORAGE_DIR: STORAGE, ENTREGA_MODO: 'agente',
                AGENTE_TOKEN: TOKEN_AGENTE, INFORMES_DIR: path.join(RAIZ, 'no-se-usa'),
                DESCARGAS_DIR: path.join(RAIZ, 'descargas'), AGENTE_ACTIVO_MS: '4000', ESPERA_ARCHIVO_MS: '8000',
            },
        });
        const fallo = setTimeout(() => rechazar(new Error('El servidor de prueba no arrancó')), 20000);
        proceso.stdout.on('data', (texto) => {
            if (String(texto).includes('Servidor corriendo')) { clearTimeout(fallo); resolver(proceso); }
        });
        proceso.stderr.on('data', (texto) => process.stderr.write(texto));
        proceso.on('exit', (codigo) => { clearTimeout(fallo); rechazar(new Error(`El servidor se cerró (código ${codigo})`)); });
    });
}

const CONFIG_AGENTE = path.join(RAIZ, 'config-agente');
const PROGRAMA_AGENTE = process.env.PROGRAMA_AGENTE || null; // para probar el .exe en vez de agente.js
const entornoBase = {
    ...process.env, AGENTE_CADA_MS: '1000', AGENTE_CATALOGO_CADA_MS: '1500', AGENTE_PEDIDOS_CADA_MS: '500',
    SON_AGENTE_PUERTO: '47999', SON_AGENTE_CONFIG: CONFIG_AGENTE, SON_AGENTE_SIN_INICIO: '1',
    SON_AGENTE_PRIMER_PLANO: '1', SON_AGENTE_SIN_ACTUALIZAR: '1', APPDATA: path.join(RAIZ, 'appdata'),
};
for (const clave of ['SON_URL', 'AGENTE_TOKEN', 'CARPETA_CLIENTES']) delete entornoBase[clave];

function lanzar(argumentos, entorno) {
    const [comando, ...resto] = PROGRAMA_AGENTE
        ? [PROGRAMA_AGENTE]
        : [process.execPath, path.join(__dirname, '..', '..', 'agente', 'agente.js')];
    const proceso = spawn(comando, [...resto, ...argumentos], { env: entorno });
    let salida = '';
    proceso.stdout.on('data', (texto) => { salida += texto; });
    proceso.stderr.on('data', (texto) => { salida += texto; });
    return { proceso, salida: () => salida };
}

// Agente con la configuración antigua (variables de entorno).
function levantarAgente(token = TOKEN_AGENTE) {
    return lanzar([], { ...entornoBase, SON_URL: BASE, AGENTE_TOKEN: token, CARPETA_CLIENTES: CLIENTES });
}

function levantarAgenteVinculado(argumentos) {
    return lanzar(argumentos, entornoBase);
}

async function esperarHasta(condicion, segundos = 15) {
    for (let i = 0; i < segundos; i++) {
        if (await condicion()) return true;
        await espera(1000);
    }
    return false;
}

// Estas variables las comparte probarProgramaInstalado con el bloque principal.
let ctx = null;

function procesosDe(rutaExe) {
    const guion = `(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $env:RUTA_EXE } | ForEach-Object { $_.ProcessId }) -join ','`;
    const salida = spawnSync('powershell', ['-NoProfile', '-Command', guion], { env: { ...process.env, RUTA_EXE: rutaExe }, encoding: 'utf8' }).stdout.trim();
    return salida ? salida.split(',').map(Number) : [];
}

function matarProcesosDe(rutaExe) {
    for (const pid of procesosDe(rutaExe)) { try { process.kill(pid); } catch (_) {} }
}

function huellaDe(contenido) {
    return require('crypto').createHash('sha256').update(contenido).digest('hex');
}

async function probarProgramaInstalado() {
    const { t, tl, informe } = ctx;
    const dirProg = path.join(RAIZ, 'programa');
    fs.mkdirSync(dirProg, { recursive: true });
    const instalado = path.join(dirProg, 'SON-Agente.exe');
    fs.copyFileSync(PROGRAMA_AGENTE, instalado);
    const original = fs.readFileSync(instalado);
    // El servidor tiene la MISMA versión que el instalado: no debe actualizarse todavía.
    fs.writeFileSync(path.join(RAIZ, 'descargas', 'SON-Agente.exe'), original);

    const entorno = {
        ...entornoBase, SON_AGENTE_PUERTO: '47998', SON_AGENTE_CONFIG: path.join(RAIZ, 'config-instalado'),
        SON_AGENTE_PRIMER_PLANO: '', SON_AGENTE_SIN_ACTUALIZAR: '', AGENTE_ACTUALIZAR_CADA_MS: '2000', AGENTE_PRIMERA_ACTUALIZACION_MS: '2000',
    };
    delete entorno.SON_AGENTE_PRIMER_PLANO; delete entorno.SON_AGENTE_SIN_ACTUALIZAR;

    // Doble clic con un código: se configura, deja el agente oculto y la ventana se cierra sola.
    const gen = await api('POST', '/api/agentes/codigo', t);
    const antes = new Set((await pool.query('SELECT id FROM agentes')).rows.map((f) => f.id));
    const ventana = spawn(instalado, [`--codigo=${gen.datos.codigo}@127.0.0.1:${PUERTO}`, `--carpeta=${CLIENTES}`], { env: entorno });
    let salidaVentana = '';
    ventana.stdout.on('data', (x) => { salidaVentana += x; });
    ventana.stderr.on('data', (x) => { salidaVentana += x; });
    const codigoSalida = await new Promise((resolver) => { ventana.on('exit', resolver); setTimeout(() => resolver('no terminó'), 30000); });
    paso('Al abrir el programa, la ventana se cierra sola (el agente queda aparte)', codigoSalida === 0, `salida ${codigoSalida}`);
    for (const fila of (await pool.query('SELECT id FROM agentes')).rows) if (!antes.has(fila.id)) ctx.limpiar.agentes.push(fila.id);

    await espera(2500);
    const pids1 = procesosDe(instalado);
    paso('Queda un agente funcionando en segundo plano', pids1.length === 1, `procesos: ${pids1.join(',')}`);

    const informeA = { ...informe, ordenId: null, cliente: 'Quinto Cliente SA', fin: '2026-10-19T20:00:00.000Z' };
    await api('POST', '/api/generar-informe', tl.datos.token, informeA);
    const llegoA = await esperarHasta(async () => pdfsEn(path.join(CLIENTES, 'Quinto Cliente SA')).length === 1);
    paso('El agente oculto entrega informes', llegoA);

    const estado = spawnSync(instalado, ['--estado'], { env: entorno, encoding: 'utf8', timeout: 20000 });
    paso('El comando --estado dice que está funcionando', /FUNCIONANDO/.test(estado.stdout || ''), (estado.stdout || estado.stderr || '').split('\n').slice(0, 3).join(' | '));

    const otraVentana = spawnSync(instalado, [], { env: entorno, encoding: 'utf8', timeout: 20000 });
    paso('Abrirlo de nuevo no crea un segundo agente', /ya está funcionando/.test(otraVentana.stdout || '') && procesosDe(instalado).length === 1);

    // Versión nueva en el servidor: el agente se actualiza solo y sigue trabajando.
    const nueva = Buffer.concat([original, Buffer.from('\n')]);
    fs.writeFileSync(path.join(RAIZ, 'descargas', 'SON-Agente.exe'), nueva);
    const actualizado = await esperarHasta(async () => huellaDe(fs.readFileSync(instalado)) === huellaDe(nueva), 30);
    paso('Con una versión nueva en el servidor, el agente se actualiza solo', actualizado);
    // (el antivirus de Windows puede demorar unos segundos en dejar arrancar el programa nuevo)
    await esperarHasta(async () => { const p = procesosDe(instalado); return p.length === 1 && p[0] !== pids1[0]; }, 20);
    await espera(1500);
    const pids2 = procesosDe(instalado);
    paso('Después de actualizarse sigue un único agente funcionando (proceso nuevo)', pids2.length === 1 && pids2[0] !== pids1[0], `antes ${pids1.join(',')} / ahora ${pids2.join(',')} | ${(() => { try { return fs.readFileSync(path.join(RAIZ, 'config-instalado', 'agente.log'), 'utf8').split('\n').slice(-8).join(' // '); } catch (e) { return e.message; } })()}`);
    paso('No quedan restos de la actualización', !fs.existsSync(`${instalado}.nuevo`), fs.readdirSync(path.dirname(instalado)).join(', '));

    const informeB = { ...informe, ordenId: null, cliente: 'Sexto Cliente SA', fin: '2026-10-19T21:00:00.000Z' };
    await api('POST', '/api/generar-informe', tl.datos.token, informeB);
    const llegoB = await esperarHasta(async () => pdfsEn(path.join(CLIENTES, 'Sexto Cliente SA')).length === 1);
    paso('Tras actualizarse, el agente sigue entregando informes', llegoB);

    // Desinstalar: se detiene, y borra el acceso directo y la configuración (de PRUEBA, en carpetas temporales).
    fs.mkdirSync(path.dirname(path.join(RAIZ, 'appdata', 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup', 'x')), { recursive: true });
    const acceso = path.join(RAIZ, 'appdata', 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup', 'SON-Agente.lnk');
    fs.writeFileSync(acceso, 'x');
    spawnSync(instalado, ['--desinstalar'], { env: entorno, encoding: 'utf8', timeout: 30000 });
    await espera(1500);
    paso('--desinstalar detiene el agente y borra su configuración', procesosDe(instalado).length === 0 && !fs.existsSync(path.join(RAIZ, 'config-instalado', 'config.json')) && !fs.existsSync(acceso));
}

// Instalación como SERVIDOR (tarea programada de Windows). Se prueba con una tarea de PRUEBA a nombre
// del usuario actual (sin administrador): lo único que no se puede probar acá es la cuenta SYSTEM.
const TAREA_PRUEBA = `SON-Agente-PRUEBA-${process.pid}`;

function consultaTarea(...extra) {
    return spawnSync('schtasks', ['/Query', '/TN', TAREA_PRUEBA, ...extra], { encoding: 'utf8' });
}

async function probarInstalacionServidor() {
    const { t, tl, informe } = ctx;
    const base = path.join(RAIZ, 'servidor');
    const dirProg = path.join(base, 'Program Files', 'SON-Agente');
    const dirConfig = path.join(base, 'ProgramData', 'SON-Agente');
    const instalado = path.join(dirProg, 'SON-Agente.exe');
    const fuente = path.join(base, 'descarga', 'SON-Agente.exe');
    fs.mkdirSync(dirProg, { recursive: true });
    fs.mkdirSync(path.dirname(fuente), { recursive: true });
    fs.copyFileSync(PROGRAMA_AGENTE, fuente);
    const original = fs.readFileSync(fuente);
    fs.writeFileSync(path.join(RAIZ, 'descargas', 'SON-Agente.exe'), original);
    // Los tiempos de prueba van en un .env junto al programa (la tarea no hereda variables de este proceso).
    fs.writeFileSync(path.join(dirProg, '.env'), [
        'AGENTE_CADA_MS=1000', 'AGENTE_CATALOGO_CADA_MS=1500', 'AGENTE_PEDIDOS_CADA_MS=500',
        'AGENTE_ACTUALIZAR_CADA_MS=2000', 'AGENTE_PRIMERA_ACTUALIZACION_MS=2000',
    ].join('\n'));

    const entorno = {
        ...entornoBase, SON_AGENTE_DIR_PROGRAMA: dirProg, SON_AGENTE_TAREA: TAREA_PRUEBA, SON_AGENTE_PRUEBA_TAREA: '1',
    };
    delete entorno.SON_AGENTE_PRIMER_PLANO; delete entorno.SON_AGENTE_SIN_ACTUALIZAR;
    const comunes = [`--config=${dirConfig}`, '--puerto=47997'];
    const correr = (exe, argumentos) => spawnSync(exe, [...argumentos, ...comunes], { env: entorno, encoding: 'utf8', timeout: 90000 });

    const gen = await api('POST', '/api/agentes/codigo', t);
    const antes = new Set((await pool.query('SELECT id FROM agentes')).rows.map((f) => f.id));
    const inst = correr(fuente, ['--instalar-servidor', `--codigo=${gen.datos.codigo}@127.0.0.1:${PUERTO}`, `--carpeta=${CLIENTES}`]);
    for (const fila of (await pool.query('SELECT id FROM agentes')).rows) if (!antes.has(fila.id)) ctx.limpiar.agentes.push(fila.id);
    paso('Instalar como servidor termina bien (y comprueba que lee la carpeta)', inst.status === 0, `salida ${inst.status}: ${(inst.stdout || inst.stderr || '').trim().split('\n').slice(-6).join(' | ')}`);
    paso('El programa quedó copiado en la carpeta de instalación', fs.existsSync(instalado) && huellaDe(fs.readFileSync(instalado)) === huellaDe(original));
    paso('La configuración quedó en la carpeta de datos del servidor', fs.existsSync(path.join(dirConfig, 'config.json')));
    const xml = consultaTarea('/XML').stdout || '';
    paso('Existe la tarea programada y no tiene límite de tiempo', consultaTarea().status === 0 && /PT0S/.test(xml));
    paso('La tarea se reintenta si falla y revisa cada 15 minutos', /RestartOnFailure/.test(xml) && /PT15M/.test(xml) && /IgnoreNew/.test(xml));
    paso('Arranca con el programa instalado (--modo-servidor)', xml.includes(instalado) && /--modo-servidor/.test(xml));
    const pidsA = procesosDe(instalado);
    paso('Hay un único agente funcionando', pidsA.length === 1, `procesos: ${pidsA.join(',')}`);

    const informeA = { ...informe, ordenId: null, cliente: 'Septimo Cliente SA', fin: '2026-10-19T22:00:00.000Z' };
    await api('POST', '/api/generar-informe', tl.datos.token, informeA);
    paso('El agente del servidor entrega informes', await esperarHasta(async () => pdfsEn(path.join(CLIENTES, 'Septimo Cliente SA')).length === 1));

    const estado = correr(instalado, ['--estado']);
    paso('--estado muestra que está funcionando como servidor', /FUNCIONANDO/.test(estado.stdout || '') && /SERVIDOR/.test(estado.stdout || ''), (estado.stdout || estado.stderr || '').split('\n').slice(0, 4).join(' | '));

    // Actualización automática dentro de la carpeta de instalación
    const nueva = Buffer.concat([original, Buffer.from('\n')]);
    fs.writeFileSync(path.join(RAIZ, 'descargas', 'SON-Agente.exe'), nueva);
    paso('Se actualiza solo en la carpeta de instalación', await esperarHasta(async () => huellaDe(fs.readFileSync(instalado)) === huellaDe(nueva), 30));
    await esperarHasta(async () => { const p = procesosDe(instalado); return p.length === 1 && p[0] !== pidsA[0]; }, 20);
    await espera(1500);
    const pidsB = procesosDe(instalado);
    paso('Tras actualizarse sigue un único agente (proceso nuevo)', pidsB.length === 1 && pidsB[0] !== pidsA[0], `antes ${pidsA.join(',')} / ahora ${pidsB.join(',')}`);
    const informeB = { ...informe, ordenId: null, cliente: 'Octavo Cliente SA', fin: '2026-10-19T23:00:00.000Z' };
    await api('POST', '/api/generar-informe', tl.datos.token, informeB);
    paso('Después de actualizarse sigue entregando', await esperarHasta(async () => pdfsEn(path.join(CLIENTES, 'Octavo Cliente SA')).length === 1));

    // Detener / iniciar
    correr(instalado, ['--detener']);
    await espera(2000);
    paso('--detener frena el agente', procesosDe(instalado).length === 0);
    correr(instalado, ['--iniciar']);
    paso('--iniciar lo vuelve a arrancar', await esperarHasta(async () => procesosDe(instalado).length === 1, 20));

    // Reinstalar encima (actualizar el programa a mano) conserva la vinculación y no duplica nada
    const otra = correr(fuente, ['--instalar-servidor']);
    paso('Reinstalar conserva la vinculación y deja un solo agente', otra.status === 0 && procesosDe(instalado).length === 1, `salida ${otra.status}: ${(otra.stdout || otra.stderr || '').trim().split('\n').slice(-4).join(' | ')}`);

    // Desinstalar desde el propio programa instalado
    const desinst = correr(instalado, ['--desinstalar']);
    await esperarHasta(async () => !fs.existsSync(dirProg), 20);
    paso('--desinstalar quita la tarea, frena el agente y borra programa y configuración',
        desinst.status === 0 && consultaTarea().status !== 0 && procesosDe(instalado).length === 0 && !fs.existsSync(dirConfig) && !fs.existsSync(dirProg));
}

(async () => {
    let servidor = null;
    let agente = null;
    let agentesPrevios = new Set();
    const limpiar = { tecnico: null, orden: null, empresa: null, empresaNueva: false, agentes: [] };
    try {
        const antes = await pool.query("SELECT id FROM empresas WHERE razon_social = 'acerbon srl'");
        limpiar.empresaNueva = antes.rowCount === 0;
        servidor = await levantarServidor();

        const admin = await api('POST', '/api/admin/login', null, { email: process.env.ADMIN_EMAIL, password: process.env.ADMIN_PASSWORD });
        const t = admin.datos.token;
        const email = `prueba.agente.${Date.now()}@son.test`;
        const tec = await api('POST', '/api/tecnicos', t, { nombre: 'Tecnico Agente', email, password: 'Prueba123' });
        limpiar.tecnico = tec.datos.id;
        const orden = await api('POST', '/api/ordenes', t, {
            tecnico_id: limpiar.tecnico, nombre_cliente: 'acerbon srl', direccion_trabajo: 'Ruta 9', descripcion_tarea: 'Revisar',
        });
        limpiar.orden = orden.datos.id;
        limpiar.empresa = orden.datos.empresa_id;
        const tl = await api('POST', '/api/tecnicos/login', null, { email, password: 'Prueba123' });

        // Seguridad del agente
        ctx = { t, tl, limpiar, informe: null };
        const sinToken = await api('GET', '/api/agente/pendientes', null);
        paso('Sin clave, el agente no puede ver nada (401)', sinToken.status === 401);
        const tokenMalo = await api('GET', '/api/agente/pendientes', null, null, { 'x-agente-token': 'otra-clave-que-no-es-la-correcta' });
        paso('Con clave incorrecta tampoco (401)', tokenMalo.status === 401);
        const comoAdmin = await api('GET', '/api/agente/pendientes', t);
        paso('Un administrador logueado no sirve como agente (401)', comoAdmin.status === 401);

        // 1) El técnico finaliza; el agente todavía no está corriendo
        const informe = {
            ordenId: limpiar.orden, cliente: 'acerbon srl', direccion: 'Ruta 9', latitud: -31.4, longitud: -64.1,
            comentarios: 'Prueba', checklist: [{ tarea: 'Revisar', hecho: true }], evidencias: [PNG],
            firmaTecnico: PNG, firmaCliente: PNG, inicio: '2026-10-19T14:00:00.000Z', fin: '2026-10-19T15:30:00.000Z', sinPdf: true,
        };
        ctx.informe = informe;
        const r1 = await api('POST', '/api/generar-informe', tl.datos.token, informe);
        paso('El servidor genera el informe aunque no haya agente', r1.status === 200 && r1.datos.ok === true);
        const est1 = await api('GET', '/api/informes/estado', t);
        paso('El panel ve 1 informe esperando y al agente desconectado', est1.datos.pendientes.length === 1 && est1.datos.servidorDisponible === false && est1.datos.modo === 'agente');

        // 2) El panel lista los informes desde el propio servidor (sin ver la carpeta de clientes)
        const carp = await api('GET', '/api/informes/carpetas', t);
        paso('El panel lista los clientes desde el servidor', carp.status === 200 && carp.datos.length === 1 && carp.datos[0].cantidad === 1, JSON.stringify(carp.datos));
        const lista1 = await api('GET', `/api/informes/carpetas/${encodeURIComponent(carp.datos[0].carpeta)}`, t);
        paso('Se ve como "en espera"', lista1.datos.length === 1 && lista1.datos[0].entregado === false);
        const bajar = await api('GET', `/api/informes/archivo/${encodeURIComponent(carp.datos[0].carpeta)}/${encodeURIComponent(lista1.datos[0].nombre)}`, t);
        paso('El administrador puede abrir el PDF desde el panel', bajar.status === 200 && bajar.datos.slice(0, 4).toString() === '%PDF');

        // 3) Se prende el agente pero la carpeta de clientes NO está disponible
        agente = levantarAgente();
        await espera(3500);
        const est2 = await api('GET', '/api/informes/estado', t);
        paso('Con la carpeta de clientes caída, el informe sigue esperando', est2.datos.pendientes.length === 1);
        paso('El panel ve al agente conectado', est2.datos.servidorDisponible === true);
        paso('El agente avisa que la carpeta no está disponible', /no está disponible/.test(agente.salida()));

        // 4) Vuelve la carpeta de clientes (con ACERBON SRL ya existente)
        fs.mkdirSync(path.join(CLIENTES, 'ACERBON SRL'), { recursive: true });
        const entregado = await esperarHasta(async () => (await api('GET', '/api/informes/estado', t)).datos.pendientes.length === 0);
        paso('Al volver la carpeta, el agente entrega el informe', entregado);
        const enCliente = pdfsEn(path.join(CLIENTES, 'ACERBON SRL'));
        paso('Quedó en la carpeta del cliente existente', enCliente.length === 1, enCliente.join(', '));
        paso('No se creó una carpeta duplicada', fs.readdirSync(CLIENTES).length === 1, fs.readdirSync(CLIENTES).join(' | '));
        const pdf = fs.readFileSync(path.join(CLIENTES, 'ACERBON SRL', enCliente[0] || 'x.pdf'));
        paso('El PDF entregado es válido', pdf.slice(0, 4).toString() === '%PDF' && pdf.length > 1000, `${pdf.length} bytes`);
        const lista2 = await api('GET', `/api/informes/carpetas/${encodeURIComponent(carp.datos[0].carpeta)}`, t);
        paso('El panel lo marca como entregado', lista2.datos.length === 1 && lista2.datos[0].entregado === true);
        const pedidoMalo = await api('POST', '/api/agente/catalogo', null, { carpetas: 'no-es-una-lista' }, { 'x-agente-token': TOKEN_AGENTE });
        paso('El servidor rechaza un catálogo inválido', pedidoMalo.status === 400);

        // 5) Un cliente nuevo sin carpeta: el agente la crea
        const informe2 = { ...informe, ordenId: null, cliente: 'Cliente Nuevo SA', fin: '2026-10-19T16:00:00.000Z' };
        await api('POST', '/api/generar-informe', tl.datos.token, informe2);
        const entregado2 = await esperarHasta(async () => pdfsEn(path.join(CLIENTES, 'Cliente Nuevo SA')).length === 1);
        paso('Para un cliente sin carpeta, el agente la crea y entrega', entregado2);

        // 6) Reenviar el mismo informe no lo duplica
        const r3 = await api('POST', '/api/generar-informe', tl.datos.token, informe);
        await espera(2500);
        paso('Reenviar el mismo informe no lo duplica', r3.datos.yaGenerado === true && pdfsEn(path.join(CLIENTES, 'ACERBON SRL')).length === 1);

        // 6b) Carpetas y PDFs que ya existían en el disco de la empresa (no pasaron por el servidor)
        const PDF_VIEJO = Buffer.from('%PDF-1.4\n% informe historico de prueba\n' + 'x'.repeat(2000) + '\n%%EOF\n');
        fs.mkdirSync(path.join(CLIENTES, 'HISTORICO SA'), { recursive: true });
        fs.writeFileSync(path.join(CLIENTES, 'HISTORICO SA', 'Informe_historico_2025.pdf'), PDF_VIEJO);
        fs.writeFileSync(path.join(CLIENTES, 'HISTORICO SA', 'Informe_borrado.pdf'), PDF_VIEJO);
        fs.writeFileSync(path.join(CLIENTES, 'ACERBON SRL', 'Informe_viejo_acerbon.pdf'), PDF_VIEJO);
        const veCarpeta = await esperarHasta(async () => (await api('GET', '/api/informes/carpetas', t)).datos.some((c) => c.empresa === 'HISTORICO SA' && c.cantidad === 2));
        paso('El panel muestra las carpetas que ya estaban en el disco de la empresa', veCarpeta);
        const todas = await api('GET', '/api/informes/carpetas', t);
        const acerbon = todas.datos.find((c) => c.empresa.toUpperCase() === 'ACERBON SRL');
        paso('Un cliente con informes viejos y nuevos los cuenta una sola vez cada uno', !!acerbon && acerbon.cantidad === 2, JSON.stringify(acerbon));
        const archAcerbon = await api('GET', `/api/informes/carpetas/${encodeURIComponent('ACERBON SRL')}`, t);
        const nombresAcerbon = archAcerbon.datos.map((a) => a.nombre);
        paso('Lista juntos los informes viejos y los entregados por SON', nombresAcerbon.length === 2 && nombresAcerbon.includes('Informe_viejo_acerbon.pdf'), nombresAcerbon.join(', '));
        paso('El informe entregado por SON sigue marcado como entregado', archAcerbon.datos.some((a) => a.entregado === true));

        const viejo = await api('GET', `/api/informes/archivo/${encodeURIComponent('HISTORICO SA')}/Informe_historico_2025.pdf`, t);
        paso('Abrir un PDF viejo: el servidor se lo pide al agente y lo entrega', viejo.status === 200 && Buffer.compare(viejo.datos, PDF_VIEJO) === 0, `status ${viejo.status}`);
        const otraVez = await api('GET', `/api/informes/archivo/${encodeURIComponent('HISTORICO SA')}/Informe_historico_2025.pdf`, t);
        paso('Abrirlo otra vez funciona (queda un rato en memoria)', otraVez.status === 200);
        const inexistente = await api('GET', `/api/informes/archivo/${encodeURIComponent('HISTORICO SA')}/Informe_que_no_existe.pdf`, t);
        paso('Un PDF que no figura en el disco da 404', inexistente.status === 404);
        const intruso = await api('GET', `/api/informes/archivo/${encodeURIComponent('HISTORICO SA/../..')}/${encodeURIComponent('../x.pdf')}`, t);
        paso('No se puede pedir archivos fuera de las carpetas', intruso.status === 404);
        fs.unlinkSync(path.join(CLIENTES, 'HISTORICO SA', 'Informe_borrado.pdf'));
        const borrado = await api('GET', `/api/informes/archivo/${encodeURIComponent('HISTORICO SA')}/Informe_borrado.pdf`, t);
        paso('Si el PDF desapareció del disco, avisa con un mensaje claro', (borrado.status === 502 && /ya no está/.test(borrado.datos.error || '')) || borrado.status === 404, `status ${borrado.status}`);
        const sinSesion = await api('GET', `/api/informes/archivo/${encodeURIComponent('HISTORICO SA')}/Informe_historico_2025.pdf`, null);
        paso('Sin sesión no se puede abrir', sinSesion.status === 401);

        // 7) Un agente con clave equivocada no recibe nada
        agente.proceso.kill();
        const impostor = levantarAgente('clave-incorrecta-pero-larga-1234567890');
        await espera(2500);
        impostor.proceso.kill();
        paso('Un agente con clave equivocada es rechazado', /no reconoce/.test(impostor.salida()));

        // Con el agente apagado, los PDFs viejos no se pueden abrir, pero la lista sigue visible
        await espera(5000);
        const sinAgente = await api('GET', `/api/informes/archivo/${encodeURIComponent('HISTORICO SA')}/Informe_historico_2025.pdf`, t);
        const masViejo = await api('GET', `/api/informes/carpetas`, t);
        paso('Con el agente apagado avisa que no está conectado (503)', sinAgente.status === 503 && /no está conectado/.test(sinAgente.datos.error || ''), `status ${sinAgente.status}`);
        paso('Con el agente apagado el panel igual ve las carpetas', masViejo.datos.some((c) => c.empresa === 'HISTORICO SA'));
        const estadoApagado = await api('GET', '/api/informes/estado', t);
        paso('El estado informa cuándo se actualizó la lista del disco', !!estadoApagado.datos.catalogoEn && estadoApagado.datos.servidorDisponible === false);

        // 8) Vinculación por código (lo que usa el .exe)
        const sinPermiso = await api('POST', '/api/agentes/codigo', tl.datos.token);
        paso('Un técnico no puede generar códigos de vinculación', sinPermiso.status === 403 || sinPermiso.status === 401, String(sinPermiso.status));
        const malo = await api('POST', '/api/agente/vincular', null, { codigo: 'AAAA-BBBB', nombre: 'x' });
        paso('Un código inventado es rechazado', malo.status === 400);
        agentesPrevios = new Set((await pool.query('SELECT id FROM agentes')).rows.map((fila) => fila.id));
        const gen = await api('POST', '/api/agentes/codigo', t);
        paso('El administrador genera un código con formato XXXX-XXXX', gen.status === 200 && /^[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(gen.datos.codigo), gen.datos.codigo);

        const informe3 = { ...informe, ordenId: null, cliente: 'Otro Cliente SA', fin: '2026-10-19T17:00:00.000Z' };
        await api('POST', '/api/generar-informe', tl.datos.token, informe3);
        const vinculado = levantarAgenteVinculado([`--codigo=${gen.datos.codigo.toLowerCase()}@127.0.0.1:${PUERTO}`, `--carpeta=${CLIENTES}`]);
        const llego = await esperarHasta(async () => pdfsEn(path.join(CLIENTES, 'Otro Cliente SA')).length === 1);
        paso('El agente se vincula con el código y entrega el informe', llego, vinculado.salida().split('\n').slice(-3).join(' | '));
        const config = fs.existsSync(path.join(CONFIG_AGENTE, 'config.json')) ? JSON.parse(fs.readFileSync(path.join(CONFIG_AGENTE, 'config.json'), 'utf8')) : {};
        paso('La configuración quedó guardada', !!config.token && config.carpeta === CLIENTES && config.url === BASE);
        const enBase = await pool.query('SELECT id, token_hash FROM agentes');
        const nuevos = enBase.rows.filter((fila) => !agentesPrevios.has(fila.id));
        for (const fila of nuevos) limpiar.agentes.push(fila.id);
        paso('En la base se guarda solo el hash de la clave, no la clave', nuevos.length === 1 && !enBase.rows.some((fila) => fila.token_hash === config.token));
        const lista = await api('GET', '/api/agentes', t);
        const miAgente = lista.datos.agentes.find((a) => a.id === nuevos[0].id);
        lista.datos.agentes = [miAgente];
        paso('El panel ve al agente activo', !!miAgente && miAgente.activo === true, JSON.stringify(miAgente));

        const reuso = await api('POST', '/api/agente/vincular', null, { codigo: gen.datos.codigo, nombre: 'x' });
        paso('El código es de un solo uso', reuso.status === 400);

        // Reiniciar el agente sin argumentos: usa la configuración guardada
        vinculado.proceso.kill();
        await espera(500);
        const informe4 = { ...informe, ordenId: null, cliente: 'Tercer Cliente SA', fin: '2026-10-19T18:00:00.000Z' };
        await api('POST', '/api/generar-informe', tl.datos.token, informe4);
        const reiniciado = levantarAgenteVinculado([]);
        const llego2 = await esperarHasta(async () => pdfsEn(path.join(CLIENTES, 'Tercer Cliente SA')).length === 1);
        paso('Al reiniciar, el agente arranca solo con la configuración guardada', llego2, reiniciado.salida().split('\n').slice(-2).join(' | '));

        // Dos agentes a la vez en la misma PC no se permiten
        const duplicado = levantarAgenteVinculado([]);
        await espera(2000);
        paso('No deja abrir un segundo agente en la misma PC', /Ya hay un agente/.test(duplicado.salida()));
        duplicado.proceso.kill();

        // Desvincular desde el panel corta el acceso
        const informe5 = { ...informe, ordenId: null, cliente: 'Cuarto Cliente SA', fin: '2026-10-19T19:00:00.000Z' };
        const baja = await api('DELETE', `/api/agentes/${lista.datos.agentes[0].id}`, t);
        paso('El administrador puede desvincular al agente', baja.status === 200);
        await api('POST', '/api/generar-informe', tl.datos.token, informe5);
        await espera(3000);
        paso('Un agente desvinculado ya no recibe informes', pdfsEn(path.join(CLIENTES, 'Cuarto Cliente SA')).length === 0 && /no reconoce/.test(reiniciado.salida()));
        reiniciado.proceso.kill();

        // Descarga del programa
        const sinExe = await api('GET', '/api/agentes/descargar', t);
        const exeFalso = path.join(RAIZ, 'descargas');
        fs.mkdirSync(exeFalso, { recursive: true });
        paso('Si el programa no está cargado, avisa con un mensaje claro', sinExe.status === 404 && /no está cargado/.test(sinExe.datos.error || ''));
        fs.writeFileSync(path.join(exeFalso, 'SON-Agente.exe'), Buffer.from('MZ-programa-de-prueba'));
        const conExe = await api('GET', '/api/agentes/descargar', t);
        paso('El administrador descarga el programa del agente', conExe.status === 200 && conExe.datos.toString().startsWith('MZ'));
        const sinTokenExe = await api('GET', '/api/agentes/descargar', null);
        paso('Sin sesión no se puede descargar', sinTokenExe.status === 401);

        // 9) El programa instalado (solo se prueba con el .exe real: PROGRAMA_AGENTE=ruta\SON-Agente.exe)
        if (PROGRAMA_AGENTE) await probarProgramaInstalado();
        if (PROGRAMA_AGENTE) await probarInstalacionServidor();
    } catch (error) {
        paso('Error inesperado', false, error.message);
    } finally {
        if (agente) agente.proceso.kill();
        if (PROGRAMA_AGENTE) {
            matarProcesosDe(path.join(RAIZ, 'programa', 'SON-Agente.exe'));
            matarProcesosDe(path.join(RAIZ, 'servidor', 'Program Files', 'SON-Agente', 'SON-Agente.exe'));
            spawnSync('schtasks', ['/Delete', '/TN', TAREA_PRUEBA, '/F'], { stdio: 'ignore' }); // por si el test falló a mitad
        }
        if (servidor) servidor.kill();
        await espera(500);
        try {
            if (limpiar.agentes.length) await pool.query('DELETE FROM agentes WHERE id = ANY($1)', [limpiar.agentes]);
            if (limpiar.orden) await pool.query('DELETE FROM ordenes WHERE id = $1', [limpiar.orden]);
            if (limpiar.tecnico) await pool.query('DELETE FROM tecnicos WHERE id = $1', [limpiar.tecnico]);
            if (limpiar.empresaNueva && limpiar.empresa) await pool.query('DELETE FROM empresas WHERE id = $1', [limpiar.empresa]);
            await pool.query("DELETE FROM tecnicos WHERE email LIKE '%@son.test'");
            console.log('Limpieza de la base hecha');
        } catch (error) {
            console.log('Limpieza con error:', error.message);
        }
        await pool.end();
        fs.rmSync(RAIZ, { recursive: true, force: true });
        console.log(fallos ? `\nRESULTADO: ${fallos} fallo(s)` : '\nRESULTADO: todo OK');
        process.exit(fallos ? 1 : 0);
    }
})();
