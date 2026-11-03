require('dotenv').config();

const express = require('express');
const cors = require('cors');
const fs = require('fs'); 
const path = require('path');

const { pool, prepararEsquema } = require('./src/db');
const {
    firmar, exigirAuth, hashSiHaceFalta, asegurarAdmin, emailValido, bcrypt,
    ROLES_DEL_PANEL, configurarRolesDelPanel, olvidarRolDeCuenta,
} = require('./src/auth');
const crypto = require('crypto');
const {
    resolverDirectorio, carpetaSegura, archivoSeguro, carpetaDisponible, prepararAlmacenLocal,
    listarPendientes, entregarPendientes, catalogoLocal, confirmarEntrega, normalizarNombre,
    RUTA_PENDIENTES, RUTA_ENVIADOS,
} = require('./src/informes');
const {
    guardarCatalogo, catalogoActualizadoEn, carpetasUnidas, archivosUnidos, buscarEnCatalogo,
    pedirArchivo, pedidosPendientes, recibirArchivo, fallarPedido, esperarArchivo,
} = require('./src/catalogo_agente');
const { crearInforme } = require('./src/pdf');
const { generarRecurrencias } = require('./src/recurrencia');
const { registrarRutasComercial, carpetaDeEmpresa } = require('./src/comercial');
const { registrarRutasTarifario, sembrarComercial } = require('./src/tarifario');
const { registrarRutasPresupuestos } = require('./src/presupuestos');
const { programarSincronizacionIPC } = require('./src/ipc');
const { registrarRutasCampo, despuesDelInforme, diaValido, puntosDe, contactoDe, avisarLosQueEstanPorSalir } = require('./src/campo');
const { ordenarRecorrido } = require('./src/ruta');
const { consultarAnalisis, crearPresupuestoDesdeComentario, normalizarChecklist } = require('./src/analisis');

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));

// --- Protección del login contra adivinar contraseñas (importante al estar en internet) ---
const MAX_INTENTOS = 8;
const BLOQUEO_MS = 15 * 60 * 1000;
const intentosFallidos = new Map();

function claveLogin(req) {
    // Detrás del túnel de Cloudflare la IP real llega en este encabezado.
    const ip = req.headers['cf-connecting-ip'] || req.ip;
    return `${ip}|${String(req.body && req.body.email || '').trim().toLowerCase()}`;
}

function limitarLogin(req, res, next) {
    const registro = intentosFallidos.get(claveLogin(req));
    if (registro && registro.bloqueadoHasta > Date.now()) {
        return res.status(429).json({ error: 'Demasiados intentos fallidos. Esperá unos minutos y probá de nuevo.' });
    }
    next();
}

function registrarFallo(req) {
    const clave = claveLogin(req);
    const registro = intentosFallidos.get(clave) || { cuenta: 0, bloqueadoHasta: 0 };
    registro.cuenta += 1;
    if (registro.cuenta >= MAX_INTENTOS) {
        registro.cuenta = 0;
        registro.bloqueadoHasta = Date.now() + BLOQUEO_MS;
    }
    intentosFallidos.set(clave, registro);
}

function limpiarFallos(req) {
    intentosFallidos.delete(claveLogin(req));
}

setInterval(() => {
    const ahora = Date.now();
    for (const [clave, registro] of intentosFallidos) {
        if (registro.bloqueadoHasta < ahora && registro.cuenta === 0) intentosFallidos.delete(clave);
    }
}, 10 * 60 * 1000).unref();

const RUTA_INFORMES = resolverDirectorio();

// Dos formas de llevar los informes a la carpeta de clientes de la empresa:
//  - "carpeta" (por defecto): este servidor ve la carpeta de clientes y copia él mismo los PDF.
//  - "agente": el servidor está en la nube y NO ve esa carpeta; un programa (agente) que corre
//    en una PC de la empresa baja los informes y los guarda en la carpeta de cada cliente.
const MODO_AGENTE = String(process.env.ENTREGA_MODO || '').trim().toLowerCase() === 'agente';
const AGENTE_TOKEN = process.env.AGENTE_TOKEN || '';
let agenteVistoEn = 0;
const AGENTE_ACTIVO_MS = Number(process.env.AGENTE_ACTIVO_MS) || 2 * 60 * 1000;

// Cuánto espera el panel a que el agente suba un PDF que solo está en el disco de la empresa.
const ESPERA_ARCHIVO_MS = Number(process.env.ESPERA_ARCHIVO_MS) || 45 * 1000;

// El programa del agente (SON-Agente.exe) se descarga desde el panel.
const RUTA_DESCARGAS = process.env.DESCARGAS_DIR || path.join(__dirname, 'descargas');
const NOMBRE_INSTALADOR = 'SON-Agente.exe';

// En modo "carpeta" copia lo que esté esperando; en modo "agente" no hace nada (lo busca el agente).
function intentarEntrega() {
    if (MODO_AGENTE) return Promise.resolve(0);
    return entregarPendientes(RUTA_INFORMES);
}

function hashToken(valor) {
    return crypto.createHash('sha256').update(String(valor)).digest();
}

function hashHex(valor) {
    return hashToken(valor).toString('hex');
}

// Los agentes se vinculan con un código de un solo uso que genera el administrador desde el panel.
// Al vincularse reciben su propia clave (se guarda solo el hash, nunca la clave en sí).
const CODIGO_VALIDO_MS = 15 * 60 * 1000;
const ALFABETO_CODIGO = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin 0/O/1/I para no confundir al leerlo
const codigosVinculacion = new Map(); // hash del código -> vencimiento

function generarCodigoVinculacion() {
    let codigo = '';
    for (let i = 0; i < 8; i++) codigo += ALFABETO_CODIGO[crypto.randomInt(ALFABETO_CODIGO.length)];
    return `${codigo.slice(0, 4)}-${codigo.slice(4)}`;
}

function normalizarCodigo(codigo) {
    return String(codigo || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

const intentosVinculacion = new Map();
function limitarVinculacion(req, res, next) {
    const ip = req.headers['cf-connecting-ip'] || req.ip;
    const registro = intentosVinculacion.get(ip);
    if (registro && registro.bloqueadoHasta > Date.now()) {
        return res.status(429).json({ error: 'Demasiados intentos. Esperá unos minutos y probá de nuevo.' });
    }
    next();
}
function registrarFalloVinculacion(req) {
    const ip = req.headers['cf-connecting-ip'] || req.ip;
    const registro = intentosVinculacion.get(ip) || { cuenta: 0, bloqueadoHasta: 0 };
    registro.cuenta += 1;
    if (registro.cuenta >= 8) {
        registro.cuenta = 0;
        registro.bloqueadoHasta = Date.now() + BLOQUEO_MS;
    }
    intentosVinculacion.set(ip, registro);
}

const ultimaMarcaAgente = new Map(); // id del agente -> última vez que se anotó en la base
const vistoAgentes = new Map(); // id del agente -> última vez que hizo un pedido (en memoria)
async function exigirAgente(req, res, next) {
    if (!MODO_AGENTE) {
        return res.status(404).json({ error: 'El modo agente no está activado en este servidor' });
    }
    const recibido = String(req.headers['x-agente-token'] || '');
    if (!recibido) return res.status(401).json({ error: 'Agente no autorizado' });
    try {
        // Clave fija del servidor (forma antigua, opcional).
        const claveFija = AGENTE_TOKEN.length >= 24 &&
            crypto.timingSafeEqual(hashToken(recibido), hashToken(AGENTE_TOKEN));
        if (!claveFija) {
            const agente = await pool.query('SELECT id FROM agentes WHERE token_hash = $1', [hashHex(recibido)]);
            if (agente.rows.length === 0) return res.status(401).json({ error: 'Agente no autorizado' });
            const id = agente.rows[0].id;
            vistoAgentes.set(id, Date.now());
            if (Date.now() - (ultimaMarcaAgente.get(id) || 0) > 30 * 1000) {
                ultimaMarcaAgente.set(id, Date.now());
                pool.query('UPDATE agentes SET visto_en = now() WHERE id = $1', [id]).catch(() => {});
            }
        }
    } catch (error) {
        console.error(error);
        return res.status(500).json({ error: 'No se pudo validar el agente' });
    }
    agenteVistoEn = Date.now();
    next();
}
// Quién puede qué (el tipo de usuario de cada cuenta del panel lo decide la base de datos):
//   - 'comercial' es la dueña de la empresa: ve todo (área técnica, área comercial y usuarios).
//   - 'admin' es Administración (técnicos superiores, empleados): solo el área técnica.
//   - 'tecnico' es la app de los técnicos.
configurarRolesDelPanel(async (id) => {
    const cuenta = await pool.query('SELECT rol FROM admins WHERE id = $1', [id]);
    return cuenta.rows[0] ? cuenta.rows[0].rol : null;
});
const soloTecnico = exigirAuth('tecnico');
// Área técnica (órdenes, técnicos, informes, análisis...): Administración y Comercial.
const usuarioDelPanel = exigirAuth(...ROLES_DEL_PANEL);
const usuarioDelPanelOTecnico = exigirAuth(...ROLES_DEL_PANEL, 'tecnico');
// Área comercial (notas por presupuestar, clientes) y usuarios del panel: solo Comercial.
const soloComercial = exigirAuth('comercial');

// Si la empresa ya existe (sin importar mayúsculas), se usa esa: así una empresa cargada por el
// área comercial y la misma escrita después en una orden son una sola.
async function buscarOCrearEmpresa(nombre, direccion) {
    const busqueda = await pool.query(
        'SELECT id FROM empresas WHERE lower(btrim(razon_social)) = lower(btrim($1)) ORDER BY id LIMIT 1',
        [nombre]
    );
    if (busqueda.rows.length > 0) return busqueda.rows[0].id;
    const nueva = await pool.query(
        'INSERT INTO empresas (razon_social, direccion_principal, carpeta_disco_k) VALUES ($1, $2, $3) RETURNING id',
        [nombre, direccion, carpetaDeEmpresa(nombre)]
    );
    return nueva.rows[0].id;
}

// Copia los puntos del formulario elegido. Si no hay formulario, la orden queda sin checklist armado.
async function leerFormulario(id) {
    const numero = Number(id);
    if (!Number.isInteger(numero) || numero <= 0) return { id: null, puntos: null };
    const fila = await pool.query('SELECT id, puntos FROM formularios_visita WHERE id = $1 AND activo = true', [numero]);
    if (!fila.rows[0]) return { id: null, puntos: null };
    return { id: fila.rows[0].id, puntos: JSON.stringify(fila.rows[0].puntos || []) };
}

// El checklist se escribe en la misma orden. Si llega la lista, esa manda.
async function checklistDe(cuerpo) {
    if (Array.isArray(cuerpo.puntos)) {
        const puntos = puntosDe(cuerpo.puntos);
        return { id: null, puntos: puntos.length ? JSON.stringify(puntos) : null };
    }
    return leerFormulario(cuerpo.formulario_id);
}

// Valida y normaliza los datos de una cuenta (administrador o técnico).
function limpiarCuenta(cuerpo, { passwordObligatoria }) {
    const nombre = String(cuerpo.nombre || '').trim();
    const email = String(cuerpo.email || '').trim().toLowerCase();
    const password = String(cuerpo.password || '');
    if (!nombre) return { error: 'Ingresá el nombre' };
    if (!emailValido(email)) return { error: 'Ingresá un correo válido, por ejemplo nombre@empresa.com' };
    if ((passwordObligatoria || password) && password.length < 6) {
        return { error: 'La contraseña debe tener al menos 6 caracteres' };
    }
    return { nombre, email, password };
}

function responderErrorCuenta(error, res, mensaje) {
    if (error.code === '23505') return res.status(409).json({ error: 'Ese correo ya está registrado' });
    console.error(error);
    return res.status(500).json({ error: mensaje });
}

app.post('/api/admin/login', limitarLogin, async (req, res) => {
    const email = (req.body.email || '').trim();
    const password = req.body.password || '';
    try {
        const resultado = await pool.query('SELECT id, nombre, email, password, rol FROM admins WHERE lower(email) = lower($1)', [email]);
        const admin = resultado.rows[0];
        if (!admin || !(await bcrypt.compare(password, admin.password))) {
            registrarFallo(req);
            return res.status(401).json({ error: 'Credenciales incorrectas' });
        }
        limpiarFallos(req);
        res.json({
            id: admin.id,
            nombre: admin.nombre,
            email: admin.email,
            rol: admin.rol,
            token: firmar({ id: admin.id, rol: admin.rol, email: admin.email }),
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error interno del servidor' });
    }
});

// Datos actuales de quien está dentro del panel (el panel los usa para confirmar que la sesión
// sigue vigente y para saber qué menú mostrar). Si la cuenta se eliminó, la sesión deja de valer.
app.get('/api/admin/yo', usuarioDelPanel, async (req, res) => {
    try {
        const resultado = await pool.query('SELECT id, nombre, email, rol FROM admins WHERE id = $1', [req.usuario.id]);
        if (!resultado.rows[0]) return res.status(401).json({ error: 'Esta cuenta ya no existe' });
        res.json(resultado.rows[0]);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error interno del servidor' });
    }
});

app.put('/api/admin/actualizar/:id', usuarioDelPanel, async (req, res) => {
    const id = Number(req.params.id);
    if (req.usuario.id !== id) return res.status(403).json({ error: 'Solo podés editar tu perfil' });
    const cuenta = limpiarCuenta(req.body, { passwordObligatoria: false });
    if (cuenta.error) return res.status(400).json({ error: cuenta.error });
    try {
        if (cuenta.password) {
            const hash = await bcrypt.hash(cuenta.password, 10);
            await pool.query('UPDATE admins SET nombre = $1, email = $2, password = $3 WHERE id = $4', [cuenta.nombre, cuenta.email, hash, id]);
        } else {
            await pool.query('UPDATE admins SET nombre = $1, email = $2 WHERE id = $3', [cuenta.nombre, cuenta.email, id]);
        }
        const actualizado = await pool.query('SELECT id, nombre, email, rol FROM admins WHERE id = $1', [id]);
        res.json(actualizado.rows[0]);
    } catch (error) {
        responderErrorCuenta(error, res, 'No se pudo actualizar el perfil');
    }
});

// Los usuarios del panel (crearlos, cambiarles el tipo, borrarlos) los maneja solo Comercial: si
// Administración pudiera hacerlo, cualquiera podría darse a sí mismo el acceso total.
app.get('/api/admin/admins', soloComercial, async (req, res) => {
    try {
        const resultado = await pool.query('SELECT id, nombre, email, rol FROM admins ORDER BY id ASC');
        res.json(resultado.rows);
    } catch (error) {
        res.status(500).json({ error: 'No se pudo leer la lista de administradores' });
    }
});

app.post('/api/admin/admins', soloComercial, async (req, res) => {
    const cuenta = limpiarCuenta(req.body, { passwordObligatoria: true });
    if (cuenta.error) return res.status(400).json({ error: cuenta.error });
    // Si no se indica el tipo, la cuenta nace con el menor acceso (Administración).
    const rol = req.body.rol === undefined || req.body.rol === null || req.body.rol === '' ? 'admin' : req.body.rol;
    if (!ROLES_DEL_PANEL.includes(rol)) return res.status(400).json({ error: 'Tipo de usuario inválido' });
    try {
        const hash = await bcrypt.hash(cuenta.password, 10);
        const resultado = await pool.query(
            'INSERT INTO admins (nombre, email, password, rol) VALUES ($1, $2, $3, $4) RETURNING id, nombre, email, rol',
            [cuenta.nombre, cuenta.email, hash, rol]
        );
        res.json(resultado.rows[0]);
    } catch (error) {
        responderErrorCuenta(error, res, 'No se pudo crear el administrador');
    }
});

// Cambia el tipo de usuario de una cuenta (Administración <-> Comercial). Rige en el acto: el servidor
// mira el tipo actual de la cuenta en cada pedido, no el que quedó anotado en su sesión.
app.put('/api/admin/admins/:id/rol', soloComercial, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'Usuario inválido' });
    const rol = req.body.rol;
    if (!ROLES_DEL_PANEL.includes(rol)) return res.status(400).json({ error: 'Tipo de usuario inválido' });
    if (id === req.usuario.id) return res.status(400).json({ error: 'No podés cambiar tu propio tipo de usuario' });
    try {
        const actualizado = await pool.query('UPDATE admins SET rol = $1 WHERE id = $2 RETURNING id, nombre, email, rol', [rol, id]);
        if (!actualizado.rows[0]) return res.status(404).json({ error: 'Ese usuario no existe' });
        olvidarRolDeCuenta(id);
        res.json(actualizado.rows[0]);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo cambiar el tipo de usuario' });
    }
});

app.delete('/api/admin/admins/:id', soloComercial, async (req, res) => {
    const id = Number(req.params.id);
    if (id === req.usuario.id) return res.status(400).json({ error: 'No podés eliminar tu propia cuenta mientras estás dentro' });
    try {
        // Siempre tiene que quedar al menos un usuario Comercial (el único que puede manejar a los demás).
        const objetivo = await pool.query('SELECT rol FROM admins WHERE id = $1', [id]);
        if (!objetivo.rows[0]) return res.status(404).json({ error: 'Ese usuario no existe' });
        if (objetivo.rows[0].rol === 'comercial') {
            const total = await pool.query("SELECT COUNT(*)::int AS cantidad FROM admins WHERE rol = 'comercial'");
            if (total.rows[0].cantidad <= 1) return res.status(400).json({ error: 'Tiene que quedar al menos un usuario Comercial' });
        }
        const borrado = await pool.query('DELETE FROM admins WHERE id = $1', [id]);
        if (!borrado.rowCount) return res.status(404).json({ error: 'Ese usuario no existe' });
        olvidarRolDeCuenta(id);
        res.json({ mensaje: 'Usuario eliminado' });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo eliminar el administrador' });
    }
});

registrarRutasComercial(app, { pool, soloComercial, usuarioDelPanel, soloTecnico });
registrarRutasCampo(app, { pool, usuarioDelPanel, soloTecnico, buscarOCrearEmpresa });
// Presupuestador (solo Comercial): inflación, tarifario, costos, parámetros y presupuestos.
registrarRutasTarifario(app, { pool, soloComercial });
registrarRutasPresupuestos(app, { pool, soloComercial });

app.post('/api/tecnicos/login', limitarLogin, async (req, res) => {
    const email = (req.body.email || '').trim();
    const password = (req.body.password || '').trim();
    try {
        const resultado = await pool.query(
            'SELECT id, nombre, email, password FROM tecnicos WHERE lower(email) = lower($1) AND activo = TRUE',
            [email]
        );
        const tecnico = resultado.rows[0];
        if (!tecnico || !(await bcrypt.compare(password, tecnico.password))) {
            registrarFallo(req);
            return res.status(401).json({ error: 'Correo o contraseña incorrectos' });
        }
        limpiarFallos(req);
        res.json({
            id: tecnico.id,
            nombre: tecnico.nombre,
            email: tecnico.email,
            // Los técnicos pueden pasar días sin señal: el token dura más para que
            // puedan sincronizar lo guardado en el celular cuando vuelvan a tener internet.
            token: firmar({ id: tecnico.id, rol: 'tecnico', email: tecnico.email }, '30d'),
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error interno del servidor' });
    }
});

app.get('/api/tecnicos', usuarioDelPanel, async (req, res) => {
    try {
        const resultado = await pool.query(
            'SELECT id, nombre, email, activo, lat, lng, ubicacion_en FROM tecnicos ORDER BY id ASC'
        );
        res.json(resultado.rows);
    } catch (error) {
        res.status(500).json({ error: 'Error del servidor' });
    }
});

app.post('/api/tecnicos', usuarioDelPanel, async (req, res) => {
    const cuenta = limpiarCuenta(req.body, { passwordObligatoria: true });
    if (cuenta.error) return res.status(400).json({ error: cuenta.error });
    try {
        const hash = await bcrypt.hash(cuenta.password, 10);
        const resultado = await pool.query(
            'INSERT INTO tecnicos (nombre, email, password) VALUES ($1, $2, $3) RETURNING id, nombre, email',
            [cuenta.nombre, cuenta.email, hash]
        );
        res.json(resultado.rows[0]);
    } catch (error) {
        responderErrorCuenta(error, res, 'Error al registrar el técnico');
    }
});

app.put('/api/tecnicos/:id', usuarioDelPanel, async (req, res) => {
    const cuenta = limpiarCuenta(req.body, { passwordObligatoria: false });
    if (cuenta.error) return res.status(400).json({ error: cuenta.error });
    try {
        if (cuenta.password) {
            const hash = await bcrypt.hash(cuenta.password, 10);
            await pool.query(
                'UPDATE tecnicos SET nombre = $1, email = $2, password = $3 WHERE id = $4',
                [cuenta.nombre, cuenta.email, hash, req.params.id]
            );
        } else {
            await pool.query('UPDATE tecnicos SET nombre = $1, email = $2 WHERE id = $3', [cuenta.nombre, cuenta.email, req.params.id]);
        }
        const actualizado = await pool.query('SELECT id, nombre, email, activo FROM tecnicos WHERE id = $1', [req.params.id]);
        if (!actualizado.rows[0]) return res.status(404).json({ error: 'Ese técnico no existe' });
        res.json(actualizado.rows[0]);
    } catch (error) {
        responderErrorCuenta(error, res, 'No se pudo editar el técnico');
    }
});

// Elimina un técnico. Sus órdenes no se borran: quedan sin técnico asignado para poder
// reasignarlas, y los informes ya generados siguen en la carpeta de cada cliente.
app.delete('/api/tecnicos/:id', usuarioDelPanel, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'Técnico inválido' });
    const cliente = await pool.connect();
    try {
        await cliente.query('BEGIN');
        const desasignadas = await cliente.query('UPDATE ordenes SET tecnico_id = NULL WHERE tecnico_id = $1', [id]);
        const borrado = await cliente.query('DELETE FROM tecnicos WHERE id = $1', [id]);
        if (!borrado.rowCount) {
            await cliente.query('ROLLBACK');
            return res.status(404).json({ error: 'Ese técnico no existe' });
        }
        await cliente.query('COMMIT');
        res.json({ mensaje: 'Técnico eliminado', ordenesSinAsignar: desasignadas.rowCount });
    } catch (error) {
        await cliente.query('ROLLBACK').catch(() => {});
        console.error(error);
        res.status(500).json({ error: 'No se pudo eliminar el técnico' });
    } finally {
        cliente.release();
    }
});

app.post('/api/tecnicos/ubicacion', soloTecnico, async (req, res) => {
    const lat = Number(req.body.lat);
    const lng = Number(req.body.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        return res.status(400).json({ error: 'Coordenadas inválidas' });
    }
    try {
        await pool.query(
            'UPDATE tecnicos SET lat = $1, lng = $2, ubicacion_en = NOW() WHERE id = $3',
            [lat, lng, req.usuario.id]
        );
        res.json({ ok: true });
    } catch (error) {
        res.status(500).json({ error: 'No se pudo guardar la ubicación' });
    }
});

app.get('/api/ordenes', usuarioDelPanel, async (req, res) => {
    try {
        const resultado = await pool.query(`
            SELECT o.*, to_char(o.fecha_asignada, 'YYYY-MM-DD') AS fecha_dia, e.razon_social AS cliente
            FROM ordenes o 
            LEFT JOIN empresas e ON o.empresa_id = e.id 
            ORDER BY o.fecha_asignada DESC NULLS LAST, o.id DESC
        `);
        res.json(resultado.rows);
    } catch (error) {
        res.status(500).json({ error: 'Error del servidor' });
    }
});

function semanaVisible() {
    const hoy = new Date();
    const dia = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
    const lunes = new Date(dia);
    lunes.setDate(dia.getDate() - ((dia.getDay() + 6) % 7));
    const domingo = new Date(lunes);
    domingo.setDate(lunes.getDate() + 6);
    const iso = (fecha) => `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, '0')}-${String(fecha.getDate()).padStart(2, '0')}`;
    return [iso(lunes), iso(domingo)];
}

app.get('/api/ordenes/tecnico/:id', soloTecnico, async (req, res) => {
    if (Number(req.params.id) !== req.usuario.id) {
        return res.status(403).json({ error: 'No podés ver órdenes de otro técnico' });
    }
    try {
        const resultado = await pool.query(`
            SELECT o.id,
                   o.direccion_trabajo AS direccion,
                   o.descripcion_tarea AS tarea,
                   o.estado,
                   o.puntos,
                   o.lat,
                   o.lng,
                   o.orden_ruta,
                   o.whatsapp_cliente AS whatsapp,
                   o.hora_ejecucion AS hora,
                   to_char(o.fecha_asignada, 'DD/MM/YYYY') AS fecha,
                   to_char(o.fecha_asignada, 'YYYY-MM-DD') AS fecha_iso,
                   e.razon_social AS cliente
            FROM ordenes o
            LEFT JOIN empresas e ON o.empresa_id = e.id
            WHERE (o.tecnico_id = $1 OR (o.pedida_por = $1 AND o.tecnico_id IS NULL))
              AND (
                o.fecha_asignada IS NULL
                OR (o.fecha_asignada >= $2::date AND o.fecha_asignada <= $3::date)
                OR (o.fecha_asignada < $2::date AND o.estado <> 'Completada')
              )
            ORDER BY o.fecha_asignada ASC NULLS LAST, o.orden_ruta ASC NULLS LAST, o.hora_ejecucion ASC NULLS LAST, o.id
        `, [req.usuario.id, ...semanaVisible()]);
        res.json(resultado.rows);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error del servidor' });
    }
});

app.post('/api/ordenes', usuarioDelPanel, async (req, res) => {
    const { 
        tecnico_id, nombre_cliente, direccion_trabajo, descripcion_tarea, 
        es_recurrente, recurrencia_valor, recurrencia_tipo, hora_ejecucion, 
        termina_condicion, termina_fecha, termina_repeticiones,
    } = req.body;
    try {
        const empresaId = await buscarOCrearEmpresa(nombre_cliente, direccion_trabajo);
        const fecha = diaValido(req.body.fecha_asignada);
        const formulario = await checklistDe(req.body);
        const contacto = contactoDe(req.body);
        if (contacto.emailInvalido) return res.status(400).json({ error: 'El correo del cliente no es válido' });
        if (contacto.whatsappInvalido) return res.status(400).json({ error: 'El WhatsApp no parece un número' });
        const nueva = await pool.query(
            `INSERT INTO ordenes (
                tecnico_id, empresa_id, direccion_trabajo, descripcion_tarea, fecha_asignada, estado,
                es_recurrente, recurrencia_valor, recurrencia_tipo, hora_ejecucion,
                termina_condicion, termina_fecha, termina_repeticiones, fecha_ocurrencia,
                formulario_id, puntos, email_cliente, whatsapp_cliente
            ) VALUES ($1,$2,$3,$4,COALESCE($12::date, CURRENT_DATE),'Pendiente',$5,$6,$7,$8,$9,$10,$11,COALESCE($12::date, CURRENT_DATE),$13,$14::jsonb,$15,$16) RETURNING *`,
            [
                tecnico_id, empresaId, direccion_trabajo, descripcion_tarea,
                es_recurrente || false, recurrencia_valor || 1, recurrencia_tipo || 'día',
                hora_ejecucion || '12:30', termina_condicion || 'Nunca', termina_fecha || null,
                termina_repeticiones || 30, fecha, formulario.id, formulario.puntos,
                contacto.email, contacto.whatsapp,
            ]
        );
        const ahora = new Date();
        const diaRuta = fecha || `${ahora.getFullYear()}-${String(ahora.getMonth() + 1).padStart(2, '0')}-${String(ahora.getDate()).padStart(2, '0')}`;
        await ordenarRecorrido(pool, tecnico_id, diaRuta);
        if (es_recurrente) await generarRecurrencias(pool, nueva.rows[0].id);
        const guardada = await pool.query(`SELECT o.*, to_char(o.fecha_asignada, 'YYYY-MM-DD') AS fecha_dia FROM ordenes o WHERE o.id = $1`, [nueva.rows[0].id]);
        res.json(guardada.rows[0]);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error al crear orden' });
    }
});

app.put('/api/ordenes/:id', usuarioDelPanel, async (req, res) => {
    const {
        tecnico_id, nombre_cliente, direccion_trabajo, descripcion_tarea,
        es_recurrente, recurrencia_valor, recurrencia_tipo, hora_ejecucion,
        termina_condicion, termina_fecha, termina_repeticiones,
    } = req.body;
    try {
        let empresaId = null;
        if (nombre_cliente) empresaId = await buscarOCrearEmpresa(nombre_cliente, direccion_trabajo);
        const fecha = diaValido(req.body.fecha_asignada);
        const formulario = await checklistDe(req.body);
        const contacto = contactoDe(req.body);
        if (contacto.emailInvalido) return res.status(400).json({ error: 'El correo del cliente no es válido' });
        if (contacto.whatsappInvalido) return res.status(400).json({ error: 'El WhatsApp no parece un número' });
        const antes = await pool.query(`SELECT tecnico_id, orden_padre_id, to_char(fecha_asignada, 'YYYY-MM-DD') AS fecha FROM ordenes WHERE id = $1`, [req.params.id]);
        await pool.query(
            `UPDATE ordenes SET
                tecnico_id = COALESCE($1, tecnico_id),
                empresa_id = COALESCE($2, empresa_id),
                direccion_trabajo = $3,
                descripcion_tarea = $4,
                es_recurrente = COALESCE($5, es_recurrente),
                recurrencia_valor = COALESCE($6, recurrencia_valor),
                recurrencia_tipo = COALESCE($7, recurrencia_tipo),
                hora_ejecucion = COALESCE($8, hora_ejecucion),
                termina_condicion = COALESCE($9, termina_condicion),
                termina_fecha = $10,
                termina_repeticiones = COALESCE($11, termina_repeticiones),
                fecha_asignada = COALESCE($13::date, fecha_asignada),
                fecha_ocurrencia = COALESCE($13::date, fecha_ocurrencia),
                formulario_id = $14,
                puntos = $15::jsonb,
                email_cliente = $16,
                whatsapp_cliente = $17,
                estado = CASE WHEN estado = 'Por asignar' AND $1::int IS NOT NULL THEN 'Pendiente' ELSE estado END
             WHERE id = $12`,
            [
                tecnico_id || null, empresaId, direccion_trabajo, descripcion_tarea,
                es_recurrente, recurrencia_valor || null, recurrencia_tipo || null,
                hora_ejecucion || null, termina_condicion || null, termina_fecha || null,
                termina_repeticiones || null, req.params.id, fecha, formulario.id, formulario.puntos,
                contacto.email, contacto.whatsapp,
            ]
        );
        const despues = await pool.query(`SELECT tecnico_id, to_char(fecha_asignada, 'YYYY-MM-DD') AS fecha FROM ordenes WHERE id = $1`, [req.params.id]);
        const pares = new Set();
        for (const fila of [...antes.rows, ...despues.rows]) {
            if (fila.tecnico_id && fila.fecha) pares.add(`${fila.tecnico_id}|${fila.fecha}`);
        }
        for (const par of pares) {
            const [tecnico, dia] = par.split('|');
            await ordenarRecorrido(pool, Number(tecnico), dia);
        }
        if (antes.rows[0] && !antes.rows[0].orden_padre_id) await generarRecurrencias(pool, Number(req.params.id));
        res.json({ mensaje: 'Actualizada' });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error al actualizar la orden' });
    }
});

app.put('/api/ordenes/:id/estado', usuarioDelPanelOTecnico, async (req, res) => {
    const estado = req.body.estado;
    const permitidos = ['Pendiente', 'En progreso', 'Completada'];
    if (!permitidos.includes(estado)) return res.status(400).json({ error: 'Estado inválido' });
    try {
        if (req.usuario.rol === 'tecnico') {
            const propia = await pool.query('SELECT tecnico_id FROM ordenes WHERE id = $1', [req.params.id]);
            if (!propia.rows[0] || propia.rows[0].tecnico_id !== req.usuario.id) {
                return res.status(403).json({ error: 'Esta orden no es tuya' });
            }
        }
        await pool.query('UPDATE ordenes SET estado = $1 WHERE id = $2', [estado, req.params.id]);
        res.json({ mensaje: 'Estado actualizado' });
    } catch (error) {
        res.status(500).json({ error: 'No se pudo cambiar el estado' });
    }
});

app.delete('/api/ordenes/:id', usuarioDelPanel, async (req, res) => {
    try {
        await pool.query('DELETE FROM ordenes WHERE id = $1', [req.params.id]);
        res.json({ mensaje: 'Eliminada' });
    } catch (error) {
        res.status(500).json({ error: 'Error' });
    }
});

app.post('/api/generar-informe', soloTecnico, async (req, res) => {
    const { cliente, direccion, comentarios, latitud, longitud, firmaTecnico, firmaCliente, evidencias, checklist, ordenId, inicio, fin, sinPdf } = req.body;
    try {
        const fechaFin = fin && !Number.isNaN(Date.parse(fin)) ? new Date(fin) : new Date();
        const nombreCliente = (cliente || 'Sin nombre').replace(/[\\/]/g, '').trim() || 'Sin nombre';
        // El informe se guarda primero en este equipo (no depende de la carpeta de red) y de ahí se
        // copia a la carpeta del cliente: enseguida si está disponible, o cuando vuelva si no.
        const dirPendiente = carpetaSegura(RUTA_PENDIENTES, nombreCliente);
        const dirEnviado = carpetaSegura(RUTA_ENVIADOS, nombreCliente);
        if (!dirPendiente || !dirEnviado) return res.status(400).json({ error: 'Nombre de cliente inválido' });
        fs.mkdirSync(dirPendiente, { recursive: true });
        const marca = fechaFin.toISOString().replace(/[:.]/g, '-');
        const sufijoOrden = ordenId ? `_orden${Number(ordenId) || 0}` : '';
        const nombreArchivo = `Informe_${marca}${sufijoOrden}.pdf`;
        const rutaCompleta = path.join(dirPendiente, nombreArchivo);
        const rutaEnviado = path.join(dirEnviado, nombreArchivo);

        // El celular reenvía el mismo informe (con la misma hora de fin) si la respuesta se perdió
        // por falta de señal. Si ese archivo ya existe, no se genera un segundo PDF.
        const yaGenerado = Boolean(fin) && (fs.existsSync(rutaCompleta) || fs.existsSync(rutaEnviado));
        if (!yaGenerado) {
            const datosTecnico = await pool.query('SELECT nombre FROM tecnicos WHERE id = $1', [req.usuario.id]);
            await crearInforme({
                destino: rutaCompleta,
                cliente, direccion, comentarios, latitud, longitud,
                tecnico: datosTecnico.rows[0] ? datosTecnico.rows[0].nombre : null,
                firmaTecnico, firmaCliente, evidencias, checklist,
                inicio, fin: fechaFin.toISOString(),
            });
        }

        let whatsapp = null;
        if (ordenId) {
            const checklistJson = Array.isArray(checklist) ? JSON.stringify(normalizarChecklist(checklist)) : null;
            const hayComentario = comentarios !== undefined;
            const comentario = hayComentario ? (String(comentarios).trim().slice(0, 4000) || null) : null;
            await pool.query(
                `UPDATE ordenes SET
                    estado = 'Completada',
                    comentarios_cierre = CASE WHEN $5::boolean THEN $3 ELSE comentarios_cierre END,
                    checklist_cierre = COALESCE($4::jsonb, checklist_cierre)
                 WHERE id = $1 AND tecnico_id = $2`,
                [ordenId, req.usuario.id, comentario, checklistJson, hayComentario]
            );
            const pdfListo = fs.existsSync(rutaCompleta) ? rutaCompleta : (fs.existsSync(rutaEnviado) ? rutaEnviado : null);
            const cierre = await despuesDelInforme(pool, {
                ordenId: Number(ordenId),
                tecnicoId: req.usuario.id,
                cliente: nombreCliente,
                inicio,
                fin: fechaFin.toISOString(),
                pdfPath: pdfListo,
                base: `${req.protocol}://${req.get('host')}`,
            });
            whatsapp = cierre && cierre.whatsapp;
        }

        if (sinPdf) {
            intentarEntrega().catch((error) => console.error('Entrega de informes:', error.message));
            return res.json({ ok: true, archivo: nombreArchivo, yaGenerado, whatsapp });
        }

        const contenido = await fs.promises.readFile(fs.existsSync(rutaCompleta) ? rutaCompleta : rutaEnviado);
        intentarEntrega().catch((error) => console.error('Entrega de informes:', error.message));
        res.setHeader('Content-Type', 'application/pdf');
        res.send(contenido);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo generar el informe' });
    }
});

const MENSAJE_SIN_SERVIDOR =
    'La carpeta de clientes del servidor no está disponible en este momento. ' +
    'Los informes nuevos no se pierden: quedan guardados y se copian solos cuando vuelva.';

// --- Agente de la empresa: baja los informes y los guarda en la carpeta de cada cliente ---
app.get('/api/agente/pendientes', exigirAgente, (req, res) => {
    const lista = listarPendientes().map(({ carpeta, archivo, ruta }) => ({
        carpeta, archivo, tamano: fs.statSync(ruta).size,
    }));
    res.json(lista);
});

app.get('/api/agente/descargar/:carpeta/:archivo', exigirAgente, (req, res) => {
    const destino = archivoSeguro(RUTA_PENDIENTES, req.params.carpeta, req.params.archivo);
    if (!destino || !fs.existsSync(destino)) return res.status(404).json({ error: 'Archivo no encontrado' });
    res.download(destino);
});

// Actualización automática del agente: informa qué versión del programa hay en el servidor
// (la huella del archivo SON-Agente.exe) y la entrega.
let huellaProgramaCache = { clave: '', hash: null };
async function huellaDelPrograma() {
    const ruta = path.join(RUTA_DESCARGAS, NOMBRE_INSTALADOR);
    if (!fs.existsSync(ruta)) return null;
    const estado = fs.statSync(ruta);
    const clave = `${estado.size}:${estado.mtimeMs}`;
    if (huellaProgramaCache.clave === clave) return { hash: huellaProgramaCache.hash, tamano: estado.size, ruta };
    const hash = await new Promise((resolver, rechazar) => {
        const calculo = crypto.createHash('sha256');
        fs.createReadStream(ruta).on('data', (parte) => calculo.update(parte)).on('end', () => resolver(calculo.digest('hex'))).on('error', rechazar);
    });
    huellaProgramaCache = { clave, hash };
    return { hash, tamano: estado.size, ruta };
}

app.get('/api/agente/programa/version', exigirAgente, async (req, res) => {
    try {
        const info = await huellaDelPrograma();
        res.json(info ? { hash: info.hash, tamano: info.tamano } : { hash: null });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo leer el programa del agente' });
    }
});

app.get('/api/agente/programa', exigirAgente, (req, res) => {
    const ruta = path.join(RUTA_DESCARGAS, NOMBRE_INSTALADOR);
    if (!fs.existsSync(ruta)) return res.status(404).json({ error: 'El programa del agente no está cargado en este servidor.' });
    res.download(ruta, NOMBRE_INSTALADOR);
});

// El agente cuenta qué carpetas y PDFs hay en el disco de la empresa (para que el panel los muestre).
app.post('/api/agente/catalogo', exigirAgente, (req, res) => {
    const guardadas = guardarCatalogo(req.body && req.body.carpetas);
    if (guardadas === null) return res.status(400).json({ error: 'Catálogo inválido' });
    res.json({ ok: true, carpetas: guardadas });
});

// Pedidos de PDFs que solo están en el disco de la empresa: el agente los consulta y los sube.
app.get('/api/agente/solicitudes', exigirAgente, (req, res) => {
    res.json(pedidosPendientes());
});

app.post('/api/agente/archivo/:id', exigirAgente, express.raw({ type: 'application/pdf', limit: '60mb' }), (req, res) => {
    const resultado = recibirArchivo(req.params.id, req.body);
    if (resultado === 'ok') return res.json({ ok: true });
    const mensajes = { desconocido: 'Ese pedido no existe o ya se cumplió', tamano: 'Tamaño de archivo inválido', formato: 'El archivo no es un PDF' };
    res.status(resultado === 'desconocido' ? 404 : 400).json({ error: mensajes[resultado] });
});

app.post('/api/agente/archivo/:id/error', exigirAgente, (req, res) => {
    const ok = fallarPedido(req.params.id, req.body && req.body.mensaje);
    res.status(ok ? 200 : 404).json({ ok });
});

app.post('/api/agente/confirmar', exigirAgente, async (req, res) => {
    try {
        const ok = await confirmarEntrega(req.body.carpeta, req.body.archivo);
        if (!ok) return res.status(404).json({ error: 'Ese informe no está en la lista de espera' });
        res.json({ ok: true });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo confirmar la entrega' });
    }
});

// El agente canjea el código de vinculación por su propia clave.
app.post('/api/agente/vincular', limitarVinculacion, async (req, res) => {
    if (!MODO_AGENTE) return res.status(404).json({ error: 'El modo agente no está activado en este servidor' });
    const hash = hashHex(normalizarCodigo(req.body.codigo));
    const vence = codigosVinculacion.get(hash);
    if (!vence || vence < Date.now()) {
        registrarFalloVinculacion(req);
        return res.status(400).json({ error: 'El código no es válido o ya venció. Generá uno nuevo desde el panel.' });
    }
    codigosVinculacion.delete(hash); // de un solo uso
    try {
        const nombre = String(req.body.nombre || '').trim().slice(0, 80) || 'Agente';
        const clave = crypto.randomBytes(32).toString('hex');
        await pool.query('INSERT INTO agentes (nombre, token_hash) VALUES ($1, $2)', [nombre, hashHex(clave)]);
        res.json({ token: clave });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo vincular el agente' });
    }
});

// --- Administración de agentes desde el panel ---
app.post('/api/agentes/codigo', usuarioDelPanel, (req, res) => {
    if (!MODO_AGENTE) return res.status(409).json({ error: 'Este servidor entrega los informes directamente en la carpeta de clientes: no necesita agente.' });
    const ahora = Date.now();
    for (const [hash, vence] of codigosVinculacion) if (vence < ahora) codigosVinculacion.delete(hash);
    const codigo = generarCodigoVinculacion();
    codigosVinculacion.set(hashHex(normalizarCodigo(codigo)), ahora + CODIGO_VALIDO_MS);
    res.json({ codigo, venceEnMinutos: CODIGO_VALIDO_MS / 60000 });
});

app.get('/api/agentes', usuarioDelPanel, async (req, res) => {
    try {
        const agentes = await pool.query('SELECT id, nombre, creado_en, visto_en FROM agentes ORDER BY id');
        res.json({
            modoAgente: MODO_AGENTE,
            descargaDisponible: fs.existsSync(path.join(RUTA_DESCARGAS, NOMBRE_INSTALADOR)),
            nombreInstalador: NOMBRE_INSTALADOR,
            agentes: agentes.rows.map((fila) => {
                // La base se actualiza cada 30 s; en memoria está la hora exacta del último pedido.
                const visto = Math.max(fila.visto_en ? new Date(fila.visto_en).getTime() : 0, vistoAgentes.get(fila.id) || 0);
                return { 
                    id: fila.id,
                    nombre: fila.nombre,
                    creadoEn: fila.creado_en,
                    vistoEn: visto ? new Date(visto).toISOString() : null,
                    activo: visto > 0 && Date.now() - visto < AGENTE_ACTIVO_MS,
                };
            }),
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo leer la lista de agentes' });
    }
});

app.get('/api/agentes/descargar', usuarioDelPanel, (req, res) => {
    const ruta = path.join(RUTA_DESCARGAS, NOMBRE_INSTALADOR);
    if (!fs.existsSync(ruta)) return res.status(404).json({ error: 'El programa del agente todavía no está cargado en este servidor.' });
    res.download(ruta, NOMBRE_INSTALADOR);
});

app.delete('/api/agentes/:id', usuarioDelPanel, async (req, res) => {
    try {
        const borrado = await pool.query('DELETE FROM agentes WHERE id = $1', [Number(req.params.id)]);
        if (borrado.rowCount === 0) return res.status(404).json({ error: 'Ese agente no existe' });
        res.json({ ok: true });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo desvincular el agente' });
    }
});

// Estado de la carpeta de clientes y de los informes que todavía esperan copiarse.
app.get('/api/informes/estado', usuarioDelPanel, async (req, res) => {
    const pendientes = listarPendientes().map(({ carpeta, archivo }) => ({ carpeta, archivo }));
    const servidorDisponible = MODO_AGENTE
        ? Date.now() - agenteVistoEn < AGENTE_ACTIVO_MS
        : await carpetaDisponible(RUTA_INFORMES);
    res.json({
        modo: MODO_AGENTE ? 'agente' : 'carpeta',
        servidorDisponible,
        pendientes,
        catalogoEn: MODO_AGENTE ? catalogoActualizadoEn() : null,
    });
});

app.get('/api/informes/pendientes/:carpeta/:archivo', usuarioDelPanel, (req, res) => {
    const destino = archivoSeguro(RUTA_PENDIENTES, req.params.carpeta, req.params.archivo);
    if (!destino || !fs.existsSync(destino)) return res.status(404).json({ error: 'Archivo no encontrado' });
    res.download(destino);
});

app.get('/api/informes/carpetas', usuarioDelPanel, async (req, res) => {
    try {
        if (MODO_AGENTE) return res.json(carpetasUnidas(catalogoLocal()));
        if (!(await carpetaDisponible(RUTA_INFORMES))) return res.status(503).json({ error: MENSAJE_SIN_SERVIDOR });
        const carpetas = fs.readdirSync(RUTA_INFORMES, { withFileTypes: true })
            .filter((entrada) => entrada.isDirectory())
            .map((entrada) => {
                const ruta = path.join(RUTA_INFORMES, entrada.name);
                const cantidad = fs.readdirSync(ruta).filter((archivo) => archivo.toLowerCase().endsWith('.pdf')).length;
                return { empresa: entrada.name.replace(/_/g, ' '), carpeta: entrada.name, cantidad };
            });
        res.json(carpetas);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo leer el disco' });
    }
});

app.get('/api/informes/carpetas/:carpeta', usuarioDelPanel, async (req, res) => {
    if (MODO_AGENTE) {
        const clave = normalizarNombre(req.params.carpeta);
        return res.json(archivosUnidos(clave, catalogoLocal().get(clave)));
    }
    if (!(await carpetaDisponible(RUTA_INFORMES))) return res.status(503).json({ error: MENSAJE_SIN_SERVIDOR });
    const dir = carpetaSegura(RUTA_INFORMES, req.params.carpeta);
    if (!dir || !fs.existsSync(dir)) return res.json([]);
    const archivos = fs.readdirSync(dir)
        .filter((archivo) => archivo.toLowerCase().endsWith('.pdf'))
        .map((archivo) => ({ nombre: archivo }));
    res.json(archivos);
});

app.get('/api/informes/archivo/:carpeta/:archivo', usuarioDelPanel, async (req, res) => {
    if (MODO_AGENTE) {
        const clave = normalizarNombre(req.params.carpeta);
        const grupo = catalogoLocal().get(clave);
        const nombre = path.basename(String(req.params.archivo || ''));
        // 1) Si el servidor tiene el PDF (informes recientes), se entrega directo.
        const archivo = grupo && grupo.archivos.find((item) => item.nombre === nombre);
        if (archivo) return res.download(archivo.ruta);
        // 2) Si solo está en el disco de la empresa, se lo pide al agente y espera a que lo suba.
        const enDisco = buscarEnCatalogo(clave, nombre);
        if (!enDisco) return res.status(404).json({ error: 'Archivo no encontrado' });
        if (Date.now() - agenteVistoEn > AGENTE_ACTIVO_MS) {
            return res.status(503).json({ error: 'Este informe está en el disco de la empresa y el agente de la oficina no está conectado ahora. Probá cuando la PC del agente esté prendida.' });
        }
        const id = pedirArchivo(enDisco.carpeta, enDisco.archivo);
        const resultado = await esperarArchivo(id, ESPERA_ARCHIVO_MS);
        if (resultado.ruta) return res.download(resultado.ruta, enDisco.archivo);
        if (resultado.agotado) return res.status(504).json({ error: 'El agente de la oficina no respondió a tiempo. Probá de nuevo en un minuto.' });
        return res.status(502).json({ error: resultado.error });
    }
    if (!(await carpetaDisponible(RUTA_INFORMES))) return res.status(503).json({ error: MENSAJE_SIN_SERVIDOR });
    const destino = archivoSeguro(RUTA_INFORMES, req.params.carpeta, req.params.archivo);
    if (!destino || !fs.existsSync(destino)) return res.status(404).json({ error: 'Archivo no encontrado' });
    res.download(destino);
});

app.get('/api/analisis', usuarioDelPanel, async (req, res) => {
    try {
        const datos = await consultarAnalisis(pool, req.query);
        if (datos.error) return res.status(datos.status || 400).json({ error: datos.error });
        res.json(datos);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo calcular el análisis' });
    }
});

app.post('/api/analisis/comentarios/:ordenId/presupuesto', soloComercial, async (req, res) => {
    try {
        const nota = await crearPresupuestoDesdeComentario(pool, Number(req.params.ordenId));
        if (nota.error) return res.status(nota.status || 400).json({ error: nota.error });
        res.json(nota);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo crear el presupuesto' });
    }
});

// El propio servidor entrega la página pública y el panel. La página abre en la raíz
// y el panel queda en /panel/, para que sonoperation.com sea la presentación.
const RUTA_PANEL = process.env.PANEL_DIR || path.join(__dirname, '..', 'son_admin', 'build', 'web');
const RUTA_TECNICO = process.env.TECNICO_DIR || path.join(__dirname, 'tecnico');
const RUTA_PRESENTACION = path.join(__dirname, 'presentacion');
const PANEL_DISPONIBLE = fs.existsSync(path.join(RUTA_PANEL, 'index.html'));
const TECNICO_DISPONIBLE = fs.existsSync(path.join(RUTA_TECNICO, 'index.html'));
// La app del técnico se abre en el celular desde /tecnico/ (misma dirección, con HTTPS).
if (TECNICO_DISPONIBLE) {
    app.use('/tecnico', (req, res, next) => {
        if (req.originalUrl.split('?')[0] === '/tecnico') return res.redirect(301, '/tecnico/');
        next();
    });
    app.use('/tecnico', express.static(RUTA_TECNICO));
}
if (PANEL_DISPONIBLE) {
    app.use('/panel', (req, res, next) => {
        if (req.originalUrl.split('?')[0] === '/panel') return res.redirect(301, '/panel/');
        next();
    });
    app.use('/panel', express.static(RUTA_PANEL));
}
app.use('/presentacion', (req, res) => {
    res.redirect(301, req.url === '/' ? '/' : req.url);
});
app.use(express.static(RUTA_PRESENTACION));

async function iniciar() {
    await pool.query('SELECT 1');
    console.log('¡Conectado exitosamente a PostgreSQL!');
    await prepararEsquema();
    await sembrarComercial(pool);
    await hashSiHaceFalta(pool, 'tecnicos');
    await asegurarAdmin(pool);
    await hashSiHaceFalta(pool, 'admins');
    await generarRecurrencias(pool);
    prepararAlmacenLocal();
    setInterval(() => {
        generarRecurrencias(pool).catch((error) => console.error('Recurrencia:', error.message));
    }, 60 * 1000);
    const avisarSalidas = () => avisarLosQueEstanPorSalir(pool).catch((error) => console.error('Aviso en camino:', error.message));
    setInterval(avisarSalidas, 60 * 1000);
    avisarSalidas();
    // Cada tanto se intenta copiar a la carpeta de clientes lo que quedó esperando.
    const cadaMs = Number(process.env.ENTREGA_CADA_MS) || 60 * 1000;
    const entregar = () => intentarEntrega().catch((error) => console.error('Entrega de informes:', error.message));
    setInterval(entregar, cadaMs);
    entregar();
    // La inflación mensual se busca sola en el INDEC (al arrancar y cada 12 horas).
    programarSincronizacionIPC(pool);

    const puerto = Number(process.env.PORT || 3000);
    app.listen(puerto, '0.0.0.0', (error) => {
        // Express 5 llama a esta función también cuando falla (por ejemplo, puerto ocupado):
        // en ese caso hay que cerrar el programa, no decir que está funcionando.
        if (error) {
            console.error(`No se pudo abrir el puerto ${puerto}: ${error.message}. ¿Ya hay un servidor corriendo?`);
            process.exit(1);
        }
        console.log(`Servidor corriendo en el puerto ${puerto}`);
        console.log(MODO_AGENTE
            ? 'Entrega de informes: por AGENTE (se vincula desde el panel: Informes > Conectar agente)'
            : `Carpeta de clientes: ${RUTA_INFORMES}`);
        console.log(`Informes en espera: ${RUTA_PENDIENTES}`);
        console.log(PANEL_DISPONIBLE ? `Panel de administración: http://localhost:${puerto}/panel/` : 'Panel no compilado (falta son_admin/build/web)');
        console.log(TECNICO_DISPONIBLE ? `App del técnico: http://localhost:${puerto}/tecnico/` : 'App del técnico no compilada');
    });
}

iniciar().catch((error) => {
    console.error('No se pudo iniciar el servidor', error);
    process.exit(1);
});
