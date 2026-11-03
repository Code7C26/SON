// Prueba qué pasa con los informes cuando la carpeta de clientes del servidor NO está disponible.
// Uso:   node test/informes-pendientes.e2e.js
// Levanta su propio servidor en el puerto 3002 con carpetas temporales (no toca las reales)
// y borra al terminar todo lo que crea.
require('dotenv').config();
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Pool } = require('pg');

const PUERTO = 3002;
const BASE = `http://127.0.0.1:${PUERTO}`;
const RAIZ = fs.mkdtempSync(path.join(os.tmpdir(), 'son_informes_'));
const CLIENTES = path.join(RAIZ, 'clientes'); // todavía NO existe: simula el servidor de archivos apagado
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

async function api(metodo, ruta, token, cuerpo) {
    const res = await fetch(BASE + ruta, {
        method: metodo,
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
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
            env: { ...process.env, PORT: String(PUERTO), INFORMES_DIR: CLIENTES, STORAGE_DIR: STORAGE, ENTREGA_CADA_MS: '1500' },
        });
        const fallo = setTimeout(() => rechazar(new Error('El servidor de prueba no arrancó')), 20000);
        proceso.stdout.on('data', (texto) => {
            if (String(texto).includes('Servidor corriendo')) {
                clearTimeout(fallo);
                resolver(proceso);
            }
        });
        proceso.stderr.on('data', (texto) => process.stderr.write(texto));
        proceso.on('exit', (codigo) => {
            clearTimeout(fallo);
            rechazar(new Error(`El servidor de prueba se cerró (código ${codigo})`));
        });
    });
}

(async () => {
    let servidor = null;
    const limpiar = { tecnico: null, orden: null, empresa: null, empresaNueva: false };
    try {
        const antes = await pool.query("SELECT id FROM empresas WHERE razon_social = 'acerbon srl'");
        limpiar.empresaNueva = antes.rowCount === 0;
        servidor = await levantarServidor();

        const admin = await api('POST', '/api/admin/login', null, { email: process.env.ADMIN_EMAIL, password: process.env.ADMIN_PASSWORD });
        const t = admin.datos.token;
        const email = `prueba.pendientes.${Date.now()}@son.test`;
        const tec = await api('POST', '/api/tecnicos', t, { nombre: 'Tecnico Pendientes', email, password: 'Prueba123' });
        limpiar.tecnico = tec.datos.id;
        const orden = await api('POST', '/api/ordenes', t, {
            tecnico_id: limpiar.tecnico, nombre_cliente: 'acerbon srl', direccion_trabajo: 'Ruta 9', descripcion_tarea: 'Revisar',
        });
        limpiar.orden = orden.datos.id;
        limpiar.empresa = orden.datos.empresa_id;
        const tl = await api('POST', '/api/tecnicos/login', null, { email, password: 'Prueba123' });

        const informe = {
            ordenId: limpiar.orden, cliente: 'acerbon srl', direccion: 'Ruta 9', latitud: -31.4, longitud: -64.1,
            comentarios: 'Prueba', checklist: [{ tarea: 'Revisar', hecho: true }], evidencias: [PNG],
            firmaTecnico: PNG, firmaCliente: PNG, inicio: '2026-10-19T14:00:00.000Z', fin: '2026-10-19T15:30:00.000Z', sinPdf: true,
        };

        // 1) La carpeta de clientes NO existe: el informe se genera igual y queda en espera.
        const r1 = await api('POST', '/api/generar-informe', tl.datos.token, informe);
        paso('Con la carpeta de clientes caída, el informe se genera igual', r1.status === 200 && r1.datos.ok === true, JSON.stringify(r1.datos));
        const estado1 = await api('GET', '/api/informes/estado', t);
        paso('El panel ve que la carpeta no está disponible', estado1.datos.servidorDisponible === false);
        paso('El informe queda en espera (1 pendiente)', estado1.datos.pendientes.length === 1, JSON.stringify(estado1.datos.pendientes));
        const orden1 = await pool.query('SELECT estado FROM ordenes WHERE id = $1', [limpiar.orden]);
        paso('La orden queda Completada igual', orden1.rows[0].estado === 'Completada');

        const pend = estado1.datos.pendientes[0];
        const bajar = await api('GET', `/api/informes/pendientes/${encodeURIComponent(pend.carpeta)}/${encodeURIComponent(pend.archivo)}`, t);
        paso('El administrador puede abrir el PDF en espera', bajar.status === 200 && Buffer.isBuffer(bajar.datos) && bajar.datos.slice(0, 4).toString() === '%PDF');
        const carpetas503 = await api('GET', '/api/informes/carpetas', t);
        paso('Listar clientes avisa con un mensaje claro (503)', carpetas503.status === 503, carpetas503.datos.error);

        // 2) Si el celular reenvía el mismo informe, no se duplica.
        const r2 = await api('POST', '/api/generar-informe', tl.datos.token, informe);
        const estado2 = await api('GET', '/api/informes/estado', t);
        paso('Reenviar el mismo informe no lo duplica', r2.datos.yaGenerado === true && estado2.datos.pendientes.length === 1);

        // 3) Vuelve la carpeta de clientes (con la carpeta ACERBON SRL ya existente).
        fs.mkdirSync(path.join(CLIENTES, 'ACERBON SRL'), { recursive: true });
        let estado3;
        for (let i = 0; i < 20; i++) {
            await espera(1000);
            estado3 = await api('GET', '/api/informes/estado', t);
            if (estado3.datos.pendientes.length === 0) break;
        }
        paso('Al volver la carpeta, el servidor copia el informe solo', estado3.datos.pendientes.length === 0 && estado3.datos.servidorDisponible === true);
        const enCliente = pdfsEn(path.join(CLIENTES, 'ACERBON SRL'));
        paso('El PDF quedó en la carpeta del cliente existente', enCliente.length === 1, enCliente.join(', '));
        paso('No se creó una carpeta duplicada', fs.readdirSync(CLIENTES).length === 1, fs.readdirSync(CLIENTES).join(' | '));
        paso('Queda una copia de respaldo en el servidor', pdfsEn(path.join(STORAGE, 'enviados', 'acerbon srl')).length === 1);
        const lista = await api('GET', '/api/informes/carpetas/ACERBON%20SRL', t);
        paso('El panel lista y puede abrir el PDF copiado', lista.status === 200 && lista.datos.length === 1);

        // 4) Reenviar después de copiado tampoco duplica.
        const r3 = await api('POST', '/api/generar-informe', tl.datos.token, informe);
        await espera(2500);
        paso('Reenviar después de copiado tampoco duplica', r3.datos.yaGenerado === true && pdfsEn(path.join(CLIENTES, 'ACERBON SRL')).length === 1);
    } catch (error) {
        paso('Error inesperado', false, error.message);
    } finally {
        if (servidor) servidor.kill();
        await espera(500);
        try {
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
