// Prueba de cuentas (técnicos y administradores) contra el servidor que está corriendo.
// Uso, con el backend prendido:   node test/cuentas.e2e.js
// Crea datos temporales (@son.test) y los borra al terminar.
require('dotenv').config();
const { Pool } = require('pg');

const BASE = process.env.PRUEBA_URL || `http://127.0.0.1:${process.env.PORT || 3000}`;
const ADMIN_EMAIL = process.env.ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;

const pool = new Pool({
    user: process.env.DB_USER, host: process.env.DB_HOST, database: process.env.DB_NAME,
    password: process.env.DB_PASSWORD, port: Number(process.env.DB_PORT || 5432),
});

let fallos = 0;
function paso(nombre, ok, detalle = '') {
    if (!ok) fallos++;
    console.log(`${ok ? 'OK   ' : 'FALLA'} ${nombre}${detalle ? ' -> ' + detalle : ''}`);
}

async function api(metodo, ruta, token, cuerpo) {
    const res = await fetch(BASE + ruta, {
        method: metodo,
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: cuerpo ? JSON.stringify(cuerpo) : undefined,
    });
    let datos = null;
    try { datos = await res.json(); } catch { /* sin cuerpo */ }
    return { status: res.status, datos };
}

(async () => {
    const limpiar = { orden: null, empresa: null, empresaNueva: false };
    try {
        const antes = await pool.query("SELECT id FROM empresas WHERE razon_social = 'cliente prueba cuentas'");
        limpiar.empresaNueva = antes.rowCount === 0;

        const login = await api('POST', '/api/admin/login', null, { email: ADMIN_EMAIL.toUpperCase(), password: ADMIN_PASSWORD });
        paso('Login del admin (sin importar mayúsculas)', login.status === 200);
        if (login.status !== 200) throw new Error('No se pudo ingresar como administrador con las credenciales del .env');
        const t = login.datos.token;

        const mal = await api('POST', '/api/tecnicos', t, { nombre: 'X', email: 'no-es-un-correo', password: 'abcdef' });
        paso('Rechaza un correo inválido', mal.status === 400, mal.datos && mal.datos.error);
        const corta = await api('POST', '/api/tecnicos', t, { nombre: 'X', email: 'x@y.com', password: '123' });
        paso('Rechaza contraseña corta', corta.status === 400, corta.datos && corta.datos.error);

        const email = `prueba.cuentas.${Date.now()}@son.test`;
        const tec = await api('POST', '/api/tecnicos', t, { nombre: 'Tecnico Cuentas', email: email.toUpperCase(), password: 'Prueba123' });
        const tecnicoId = tec.datos.id;
        paso('Crea técnico (correo guardado en minúsculas)', tec.status === 200 && tec.datos.email === email, tec.datos.email);
        const dup = await api('POST', '/api/tecnicos', t, { nombre: 'Otro', email, password: 'Prueba123' });
        paso('Correo repetido da un mensaje claro', dup.status === 409, dup.datos && dup.datos.error);
        const lt = await api('POST', '/api/tecnicos/login', null, { email: email.toUpperCase(), password: 'Prueba123' });
        paso('El técnico ingresa aunque escriba el correo en mayúsculas', lt.status === 200);

        const orden = await api('POST', '/api/ordenes', t, {
            tecnico_id: tecnicoId, nombre_cliente: 'cliente prueba cuentas', direccion_trabajo: 'Calle 1', descripcion_tarea: 'Tarea',
        });
        limpiar.orden = orden.datos.id;
        limpiar.empresa = orden.datos.empresa_id;
        const del = await api('DELETE', `/api/tecnicos/${tecnicoId}`, t);
        paso('Elimina el técnico', del.status === 200 && del.datos.ordenesSinAsignar === 1, JSON.stringify(del.datos));
        const fila = await pool.query('SELECT tecnico_id FROM ordenes WHERE id = $1', [limpiar.orden]);
        paso('La orden se conserva, sin técnico', fila.rowCount === 1 && fila.rows[0].tecnico_id === null);
        const lt2 = await api('POST', '/api/tecnicos/login', null, { email, password: 'Prueba123' });
        paso('El técnico eliminado ya no puede ingresar', lt2.status === 401);
        const nada = await api('DELETE', '/api/tecnicos/99999', t);
        paso('Eliminar uno inexistente da 404', nada.status === 404);

        const emailAdmin = `admin.prueba.${Date.now()}@son.test`;
        const a = await api('POST', '/api/admin/admins', t, { nombre: 'Admin Prueba', email: emailAdmin, password: 'Prueba123' });
        paso('Crea un administrador nuevo', a.status === 200 && !!a.datos.id);
        const adup = await api('POST', '/api/admin/admins', t, { nombre: 'Admin', email: emailAdmin, password: 'Prueba123' });
        paso('Administrador con correo repetido: mensaje claro', adup.status === 409, adup.datos && adup.datos.error);
        const la = await api('POST', '/api/admin/login', null, { email: emailAdmin, password: 'Prueba123' });
        paso('El nuevo administrador ingresa al panel', la.status === 200);
        const lista = await api('GET', '/api/admin/admins', t);
        paso('Lista de administradores', lista.status === 200 && lista.datos.length >= 2);
        const sinToken = await api('GET', '/api/admin/admins', null);
        paso('La lista exige estar logueado', sinToken.status === 401);

        const otroTec = await api('POST', '/api/tecnicos', t, { nombre: 'T', email: `t.${Date.now()}@son.test`, password: 'Prueba123' });
        const tl = await api('POST', '/api/tecnicos/login', null, { email: otroTec.datos.email, password: 'Prueba123' });
        const prohibido = await api('POST', '/api/admin/admins', tl.datos.token, { nombre: 'Intruso', email: 'intruso@son.test', password: 'abcdef' });
        paso('Un técnico NO puede crear administradores', prohibido.status === 403);
        await api('DELETE', `/api/tecnicos/${otroTec.datos.id}`, t);

        const yo = await api('DELETE', `/api/admin/admins/${login.datos.id}`, t);
        paso('No se puede eliminar la propia cuenta', yo.status === 400, yo.datos && yo.datos.error);
        const delAdmin = await api('DELETE', `/api/admin/admins/${a.datos.id}`, t);
        paso('Elimina el administrador de prueba', delAdmin.status === 200);
    } catch (error) {
        paso('Error inesperado', false, error.message);
    } finally {
        try {
            if (limpiar.orden) await pool.query('DELETE FROM ordenes WHERE id = $1', [limpiar.orden]);
            if (limpiar.empresaNueva && limpiar.empresa) await pool.query('DELETE FROM empresas WHERE id = $1', [limpiar.empresa]);
            await pool.query("DELETE FROM tecnicos WHERE email LIKE '%@son.test'");
            await pool.query("DELETE FROM admins WHERE email LIKE '%@son.test'");
            console.log('Limpieza hecha');
        } catch (error) {
            console.log('Limpieza con error:', error.message);
        }
        await pool.end();
        console.log(fallos ? `\nRESULTADO: ${fallos} fallo(s)` : '\nRESULTADO: todo OK');
        process.exit(fallos ? 1 : 0);
    }
})();
