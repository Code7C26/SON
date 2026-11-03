const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

function firmar(payload, expira = '12h') {
    return jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: expira });
}

function leerToken(req) {
    const header = req.headers.authorization || '';
    if (header.startsWith('Bearer ')) return header.slice(7);
    if (typeof req.query.token === 'string') return req.query.token;
    return null;
}

// Tipos de usuario del panel:
//   'comercial' = acceso total (la dueña de la empresa): área técnica, área comercial y usuarios.
//   'admin'     = Administración (técnicos superiores, empleados): solo el área técnica.
const ROLES_DEL_PANEL = ['admin', 'comercial'];

// El tipo de usuario de una cuenta del panel se consulta en la base (y se recuerda unos segundos) en vez
// de confiar solo en lo que dice el token. Así, si se cambia el tipo de una persona o se borra su cuenta,
// el cambio rige enseguida y no recién cuando se le vence la sesión (12 horas).
const VIGENCIA_ROL_MS = 10 * 1000;
const rolesRecordados = new Map(); // id de la cuenta -> { rol (null si ya no existe), hasta }
let leerRolDeCuenta = null;

function configurarRolesDelPanel(leer) {
    leerRolDeCuenta = leer;
    rolesRecordados.clear();
}

// Hay que llamarla cuando se cambia el tipo de una cuenta o se la borra, para que se note en el acto.
function olvidarRolDeCuenta(id) {
    rolesRecordados.delete(Number(id));
}

async function rolActualDeCuenta(id) {
    const recordado = rolesRecordados.get(id);
    if (recordado && recordado.hasta > Date.now()) return recordado.rol;
    const rol = await leerRolDeCuenta(id);
    if (rolesRecordados.size >= 1000) rolesRecordados.clear();
    rolesRecordados.set(id, { rol, hasta: Date.now() + VIGENCIA_ROL_MS });
    return rol;
}

function exigirAuth(...roles) {
    return async (req, res, next) => {
        const token = leerToken(req);
        if (!token) return res.status(401).json({ error: 'No autorizado' });
        let datos;
        try {
            datos = jwt.verify(token, process.env.JWT_SECRET);
        } catch {
            return res.status(401).json({ error: 'Sesión vencida o inválida' });
        }
        if (leerRolDeCuenta && ROLES_DEL_PANEL.includes(datos.rol)) {
            try {
                const actual = await rolActualDeCuenta(Number(datos.id));
                if (!actual) return res.status(401).json({ error: 'Esta cuenta ya no existe' });
                datos = { ...datos, rol: actual };
            } catch (error) {
                console.error(error);
                return res.status(500).json({ error: 'No se pudo validar la sesión' });
            }
        }
        if (roles.length && !roles.includes(datos.rol)) {
            return res.status(403).json({ error: 'No tenés permiso para esta acción' });
        }
        req.usuario = datos;
        next();
    };
}

async function hashSiHaceFalta(pool, tabla) {
    const filas = await pool.query(`SELECT id, password FROM ${tabla}`);
    for (const fila of filas.rows) {
        if (!String(fila.password).startsWith('$2')) {
            const hash = await bcrypt.hash(fila.password, 10);
            await pool.query(`UPDATE ${tabla} SET password = $1 WHERE id = $2`, [hash, fila.id]);
        }
    }
}

function emailValido(email) {
    return typeof email === 'string' && email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email);
}

// Solo crea el usuario inicial cuando todavía no hay ninguno. Así, si el usuario de prueba se
// cambia o se borra, no vuelve a aparecer en cada reinicio. El usuario inicial es de tipo "comercial"
// (acceso total) porque es el que después crea a los demás.
// Además, siempre tiene que existir al menos una cuenta con acceso total: si no hay ninguna (por
// ejemplo, cuentas creadas antes de que existieran los tipos de usuario), la más antigua pasa a serlo.
async function asegurarAdmin(pool) {
    const email = process.env.ADMIN_EMAIL;
    const existe = await pool.query('SELECT id FROM admins LIMIT 1');
    if (existe.rows.length === 0) {
        const hash = await bcrypt.hash(process.env.ADMIN_PASSWORD, 10);
        await pool.query(
            "INSERT INTO admins (nombre, email, password, rol) VALUES ($1, $2, $3, 'comercial')",
            [process.env.ADMIN_NOMBRE || 'Administrador', email, hash]
        );
    }
    await pool.query(
        `UPDATE admins SET rol = 'comercial'
         WHERE id = (SELECT MIN(id) FROM admins)
           AND NOT EXISTS (SELECT 1 FROM admins WHERE rol = 'comercial')`
    );
}

module.exports = {
    firmar, exigirAuth, hashSiHaceFalta, asegurarAdmin, emailValido, bcrypt,
    ROLES_DEL_PANEL, configurarRolesDelPanel, olvidarRolDeCuenta,
};
