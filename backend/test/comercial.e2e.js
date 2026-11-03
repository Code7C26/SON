// Prueba de los tipos de usuario del panel y del área comercial (notas del técnico, bandeja y clientes)
// contra el servidor que está corriendo.
//   - Comercial (la dueña de la empresa) ve todo: área técnica, área comercial y usuarios.
//   - Administración (técnicos superiores, empleados) ve solo el área técnica.
// Uso, con el backend prendido:   node test/comercial.e2e.js
// Crea datos temporales (@son.test, "Cliente Prueba Comercial ...") y los borra al terminar.
require('dotenv').config();
const { Pool } = require('pg');
const { asegurarAdmin } = require('../src/auth');

const BASE = process.env.PRUEBA_URL || `http://127.0.0.1:${process.env.PORT || 3000}`;
const ADMIN_EMAIL = process.env.ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;
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

async function api(metodo, ruta, token, cuerpo) {
    const res = await fetch(BASE + ruta, {
        method: metodo,
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: cuerpo ? JSON.stringify(cuerpo) : undefined,
    });
    let datos = null;
    const tipo = res.headers.get('content-type') || '';
    if (tipo.includes('application/json')) {
        try { datos = await res.json(); } catch { /* sin cuerpo */ }
    } else {
        datos = Buffer.from(await res.arrayBuffer());
    }
    return { status: res.status, datos, tipo };
}

// Hace cambios en la base que se deshacen siempre al terminar (no quedan en la base real).
async function enTransaccion(trabajo) {
    const cliente = await pool.connect();
    try {
        await cliente.query('BEGIN');
        await trabajo(cliente);
    } finally {
        await cliente.query('ROLLBACK').catch(() => {});
        cliente.release();
    }
}

(async () => {
    const marca = Date.now();
    const empresaA = `Cliente Prueba Comercial ${marca}`;
    try {
        const login = await api('POST', '/api/admin/login', null, { email: ADMIN_EMAIL, password: ADMIN_PASSWORD });
        paso('La cuenta principal ingresa con acceso total (tipo Comercial)', login.status === 200 && login.datos.rol === 'comercial', `rol=${login.datos && login.datos.rol}`);
        if (login.status !== 200) throw new Error('No se pudo ingresar con las credenciales del .env');
        const duena = login.datos.token;
        const duenaId = login.datos.id;

        // --- Tipos de usuario: Comercial (todo) y Administración (solo el área técnica) ---
        const emailCom = `comercial.${marca}@son.test`;
        const emailAdm = `administracion.${marca}@son.test`;
        const emailSinTipo = `sintipo.${marca}@son.test`;
        const malRol = await api('POST', '/api/admin/admins', duena, { nombre: 'X', email: `x.${marca}@son.test`, password: 'Prueba123', rol: 'dueño' });
        paso('Rechaza un tipo de usuario inventado', malRol.status === 400, malRol.datos && malRol.datos.error);
        const com = await api('POST', '/api/admin/admins', duena, { nombre: 'Comercial Prueba', email: emailCom, password: 'Prueba123', rol: 'comercial' });
        paso('Crea un usuario Comercial', com.status === 200 && com.datos.rol === 'comercial');
        const comId = com.datos.id;
        const adm0 = await api('POST', '/api/admin/admins', duena, { nombre: 'Administracion Prueba', email: emailAdm, password: 'Prueba123', rol: 'admin' });
        paso('Crea un usuario de Administración', adm0.status === 200 && adm0.datos.rol === 'admin');
        const admId = adm0.datos.id;
        const sinTipo = await api('POST', '/api/admin/admins', duena, { nombre: 'Sin Tipo', email: emailSinTipo, password: 'Prueba123' });
        paso('Sin indicar tipo, la cuenta nace con el menor acceso (Administración)', sinTipo.status === 200 && sinTipo.datos.rol === 'admin');
        const sinTipoId = sinTipo.datos.id;

        const lc = await api('POST', '/api/admin/login', null, { email: emailCom, password: 'Prueba123' });
        paso('Comercial ingresa y el servidor le dice su tipo', lc.status === 200 && lc.datos.rol === 'comercial');
        const c = lc.datos.token;
        const la = await api('POST', '/api/admin/login', null, { email: emailAdm, password: 'Prueba123' });
        paso('Administración ingresa y el servidor le dice su tipo', la.status === 200 && la.datos.rol === 'admin');
        const adm = la.datos.token;
        const ls = await api('POST', '/api/admin/login', null, { email: emailSinTipo, password: 'Prueba123' });
        const s = ls.datos.token;

        const yoC = await api('GET', '/api/admin/yo', c);
        paso('/api/admin/yo devuelve los datos de Comercial', yoC.status === 200 && yoC.datos.rol === 'comercial' && yoC.datos.email === emailCom);
        const yoA = await api('GET', '/api/admin/yo', adm);
        paso('/api/admin/yo devuelve los datos de Administración', yoA.status === 200 && yoA.datos.rol === 'admin' && yoA.datos.email === emailAdm);
        const yoSin = await api('GET', '/api/admin/yo', null);
        paso('/api/admin/yo exige estar logueado', yoSin.status === 401);

        // --- Administración: solo el área técnica ---
        for (const [ruta, nombre] of [['/api/tecnicos', 'técnicos'], ['/api/ordenes', 'órdenes'], ['/api/analisis', 'análisis']]) {
            const r = await api('GET', ruta, adm);
            paso(`Administración ve ${nombre}`, r.status === 200, `status ${r.status}`);
        }
        const informesAdm = await api('GET', '/api/informes/carpetas', adm);
        paso('Administración puede entrar a informes', informesAdm.status !== 401 && informesAdm.status !== 403, `status ${informesAdm.status}`);
        for (const [metodo, ruta, etiqueta, cuerpo] of [
            ['GET', '/api/admin/admins', 'Administración NO ve la lista de usuarios'],
            ['GET', '/api/solicitudes-presupuesto', 'Administración NO ve las notas por presupuestar'],
            ['GET', '/api/solicitudes-presupuesto/resumen', 'Administración NO ve el resumen de notas'],
            ['GET', '/api/solicitudes-presupuesto/1/foto', 'Administración NO ve las fotos de las notas'],
            ['PUT', '/api/solicitudes-presupuesto/1', 'Administración NO puede cambiar una nota', { estado: 'Descartada' }],
            ['GET', '/api/clientes', 'Administración NO ve las fichas de clientes'],
            ['POST', '/api/clientes', 'Administración NO puede crear una ficha de cliente', { razon_social: `Intruso ${marca}` }],
            ['PUT', '/api/clientes/1', 'Administración NO puede editar una ficha de cliente', { razon_social: `Intruso ${marca}` }],
            ['POST', '/api/admin/admins', 'Administración NO puede crear usuarios', { nombre: 'Intruso', email: `intruso.${marca}@son.test`, password: 'Prueba123', rol: 'comercial' }],
            ['PUT', `/api/admin/admins/${admId}/rol`, 'Administración NO puede subirse a Comercial', { rol: 'comercial' }],
            ['PUT', `/api/admin/admins/${comId}/rol`, 'Administración NO puede cambiarle el tipo a otro', { rol: 'admin' }],
            ['DELETE', `/api/admin/admins/${comId}`, 'Administración NO puede borrar usuarios'],
        ]) {
            const r = await api(metodo, ruta, adm, cuerpo);
            paso(etiqueta, r.status === 403, `status ${r.status}`);
        }
        const miPerfilA = await api('PUT', `/api/admin/actualizar/${admId}`, adm, { nombre: 'Administracion Cambiada', email: emailAdm });
        paso('Administración puede editar su propio perfil (sigue siendo Administración)', miPerfilA.status === 200 && miPerfilA.datos.nombre === 'Administracion Cambiada' && miPerfilA.datos.rol === 'admin');
        const perfilAjeno = await api('PUT', `/api/admin/actualizar/${duenaId}`, adm, { nombre: 'Hackeado', email: 'h@son.test' });
        paso('Administración NO puede editar el perfil de otro', perfilAjeno.status === 403);

        // --- Comercial: ve todo ---
        for (const [ruta, nombre] of [
            ['/api/tecnicos', 'técnicos'], ['/api/ordenes', 'órdenes'], ['/api/analisis', 'análisis'], ['/api/informes/carpetas', 'informes'],
            ['/api/admin/admins', 'usuarios'], ['/api/clientes', 'clientes'], ['/api/solicitudes-presupuesto', 'las notas por presupuestar'], ['/api/solicitudes-presupuesto/resumen', 'el resumen de notas'],
        ]) {
            const r = await api('GET', ruta, c);
            paso(`Comercial ve ${nombre}`, r.status !== 401 && r.status !== 403, `status ${r.status}`);
        }
        const miPerfilC = await api('PUT', `/api/admin/actualizar/${comId}`, c, { nombre: 'Comercial Cambiado', email: emailCom });
        paso('Comercial puede editar su propio perfil (sigue siendo Comercial)', miPerfilC.status === 200 && miPerfilC.datos.nombre === 'Comercial Cambiado' && miPerfilC.datos.rol === 'comercial');
        const perfilAjenoC = await api('PUT', `/api/admin/actualizar/${duenaId}`, c, { nombre: 'Hackeado', email: 'h@son.test' });
        paso('Nadie edita el perfil de otro (ni siquiera Comercial)', perfilAjenoC.status === 403);

        // --- Cambiar el tipo de usuario: rige en el acto, aunque la persona tenga la sesión abierta ---
        const antes = await api('GET', '/api/clientes', s);
        paso('Un usuario de Administración con la sesión abierta no ve los clientes', antes.status === 403);
        const sube = await api('PUT', `/api/admin/admins/${sinTipoId}/rol`, duena, { rol: 'comercial' });
        paso('Comercial puede cambiar el tipo de otro usuario', sube.status === 200 && sube.datos.rol === 'comercial');
        const despues = await api('GET', '/api/clientes', s);
        paso('Al subirlo a Comercial, su sesión abierta ve los clientes enseguida', despues.status === 200, `status ${despues.status}`);
        const baja = await api('PUT', `/api/admin/admins/${sinTipoId}/rol`, c, { rol: 'admin' });
        paso('Otro usuario Comercial también puede cambiar el tipo de los demás', baja.status === 200 && baja.datos.rol === 'admin');
        const sinAcceso = await api('GET', '/api/clientes', s);
        paso('Al bajarlo a Administración, su sesión abierta pierde el acceso enseguida', sinAcceso.status === 403, `status ${sinAcceso.status}`);
        const sigueTecnico = await api('GET', '/api/tecnicos', s);
        paso('...pero sigue viendo el área técnica', sigueTecnico.status === 200);
        const propioRol = await api('PUT', `/api/admin/admins/${duenaId}/rol`, duena, { rol: 'admin' });
        paso('Nadie puede cambiar su propio tipo (no se puede quedar sin Comercial)', propioRol.status === 400, propioRol.datos && propioRol.datos.error);
        const rolMalo = await api('PUT', `/api/admin/admins/${sinTipoId}/rol`, duena, { rol: 'cualquiera' });
        paso('Rechaza un tipo de usuario inválido al cambiarlo', rolMalo.status === 400);
        const rolNadie = await api('PUT', '/api/admin/admins/99999999/rol', duena, { rol: 'admin' });
        paso('Cambiar el tipo de un usuario inexistente da 404', rolNadie.status === 404);

        // --- Siempre tiene que existir una cuenta con acceso total (se prueba sin tocar la base real) ---
        await enTransaccion(async (cliente) => {
            await cliente.query("UPDATE admins SET rol = 'admin'");
            await asegurarAdmin(cliente);
            const filas = (await cliente.query('SELECT id, rol FROM admins ORDER BY id')).rows;
            paso('Si ninguna cuenta tiene acceso total, la más antigua lo recupera', filas[0].rol === 'comercial' && filas.slice(1).every((f) => f.rol === 'admin'), JSON.stringify(filas));
        });
        await enTransaccion(async (cliente) => {
            await cliente.query("UPDATE admins SET rol = 'admin'");
            await cliente.query("UPDATE admins SET rol = 'comercial' WHERE id = $1", [comId]);
            await asegurarAdmin(cliente);
            const filas = (await cliente.query('SELECT id, rol FROM admins ORDER BY id')).rows;
            const conAcceso = filas.filter((f) => f.rol === 'comercial');
            paso('Si ya hay una cuenta con acceso total, no se toca a nadie más', conAcceso.length === 1 && conAcceso[0].id === comId, JSON.stringify(filas));
        });
        await enTransaccion(async (cliente) => {
            await cliente.query('DELETE FROM admins');
            await asegurarAdmin(cliente);
            const filas = (await cliente.query('SELECT email, rol FROM admins')).rows;
            paso('Con la tabla vacía se crea la cuenta inicial con acceso total', filas.length === 1 && filas[0].rol === 'comercial' && filas[0].email === ADMIN_EMAIL, JSON.stringify(filas));
        });

        // --- Una visita de un técnico (las órdenes las cargan los técnicos superiores: Administración) ---
        const emailTec = `tec.comercial.${marca}@son.test`;
        const tec = await api('POST', '/api/tecnicos', adm, { nombre: 'Tecnico Comercial', email: emailTec, password: 'Prueba123' });
        paso('Administración crea un técnico', tec.status === 200, `status ${tec.status}`);
        const tecnicoId = tec.datos.id;
        const lt = await api('POST', '/api/tecnicos/login', null, { email: emailTec, password: 'Prueba123' });
        const t = lt.datos.token;
        const orden = await api('POST', '/api/ordenes', adm, { tecnico_id: tecnicoId, nombre_cliente: empresaA, direccion_trabajo: 'Calle 123', descripcion_tarea: 'Revisión' });
        paso('Administración crea una orden de trabajo', orden.status === 200, `status ${orden.status}`);
        const ordenId = orden.datos.id;

        // Los nombres de las empresas los puede pedir Administración (para sugerir clientes en las órdenes),
        // pero sin teléfono, CUIT ni ningún dato de contacto.
        const nombres = await api('GET', '/api/clientes/nombres', adm);
        paso(
            'Administración ve los nombres de las empresas, sin datos de contacto',
            nombres.status === 200 && Array.isArray(nombres.datos) && nombres.datos.some((x) => x.razon_social === empresaA)
                && nombres.datos.every((x) => Object.keys(x).sort().join() === 'id,razon_social'),
            nombres.status !== 200 ? `status ${nombres.status}` : ''
        );
        const nombresCom = await api('GET', '/api/clientes/nombres', c);
        paso('Comercial también ve los nombres de las empresas', nombresCom.status === 200);
        const nombresSin = await api('GET', '/api/clientes/nombres', null);
        paso('Los nombres de las empresas exigen estar logueado', nombresSin.status === 401);

        // --- Notas del técnico ---
        const idA = `prueba-comercial-${marca}-a`;
        const nota = { idCliente: idA, ordenId, cliente: empresaA, descripcion: '  Falta extintor ABC 5 kg  ', cantidad: 2, foto: PNG };
        const n1 = await api('POST', '/api/solicitudes-presupuesto', t, nota);
        paso('El técnico anota algo para presupuestar', n1.status === 200 && n1.datos.ok === true && n1.datos.yaExistia === false, JSON.stringify(n1.datos));
        const n1bis = await api('POST', '/api/solicitudes-presupuesto', t, nota);
        paso('Si la nota se reenvía (sin señal) no se duplica', n1bis.status === 200 && n1bis.datos.yaExistia === true && n1bis.datos.id === n1.datos.id);
        const cuenta = await pool.query('SELECT COUNT(*)::int AS n FROM solicitudes_presupuesto WHERE id_cliente = $1', [idA]);
        paso('Queda una sola nota en la base', cuenta.rows[0].n === 1);

        const sinTexto = await api('POST', '/api/solicitudes-presupuesto', t, { ...nota, idCliente: `${idA}-1`, descripcion: '   ' });
        paso('Rechaza una nota vacía', sinTexto.status === 400, sinTexto.datos && sinTexto.datos.error);
        const cantMala = await api('POST', '/api/solicitudes-presupuesto', t, { ...nota, idCliente: `${idA}-2`, cantidad: 0 });
        paso('Rechaza cantidad 0', cantMala.status === 400);
        const cantRara = await api('POST', '/api/solicitudes-presupuesto', t, { ...nota, idCliente: `${idA}-3`, cantidad: 2.5 });
        paso('Rechaza cantidad con decimales', cantRara.status === 400);
        const sinId = await api('POST', '/api/solicitudes-presupuesto', t, { ...nota, idCliente: 'a' });
        paso('Rechaza identificador inválido', sinId.status === 400);
        const largo = await api('POST', '/api/solicitudes-presupuesto', t, { ...nota, idCliente: `${idA}-4`, descripcion: 'x'.repeat(501) });
        paso('Rechaza descripción demasiado larga', largo.status === 400);
        const noImagen = await api('POST', '/api/solicitudes-presupuesto', t, { ...nota, idCliente: `${idA}-5`, foto: 'data:image/png;base64,SG9sYSBtdW5kbw==' });
        paso('Rechaza una "foto" que no es imagen', noImagen.status === 400, noImagen.datos && noImagen.datos.error);
        const enorme = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(5 * 1024 * 1024)]).toString('base64');
        const grande = await api('POST', '/api/solicitudes-presupuesto', t, { ...nota, idCliente: `${idA}-6`, foto: `data:image/jpeg;base64,${enorme}` });
        paso('Rechaza una foto de más de 4 MB', grande.status === 400, grande.datos && grande.datos.error);
        const sinFoto = await api('POST', '/api/solicitudes-presupuesto', t, { idCliente: `${idA}-7`, ordenId, descripcion: 'Falta señalética de salida', cantidad: '3' });
        paso('Una nota sin foto y con cantidad como texto se acepta', sinFoto.status === 200 && sinFoto.datos.yaExistia === false);
        const sinOrden = await api('POST', '/api/solicitudes-presupuesto', t, { idCliente: `${idA}-8`, cliente: empresaA.toUpperCase(), descripcion: 'Botiquín' });
        paso('Una nota sin orden se asocia a la empresa por su nombre', sinOrden.status === 200);

        const deAdm = await api('POST', '/api/solicitudes-presupuesto', adm, nota);
        const deDuena = await api('POST', '/api/solicitudes-presupuesto', duena, nota);
        paso('Solo el técnico puede anotar (ni Administración ni Comercial)', deAdm.status === 403 && deDuena.status === 403);
        const tecLista = await api('GET', '/api/solicitudes-presupuesto', t);
        paso('El técnico NO ve la bandeja comercial', tecLista.status === 403);
        const tecClientes = await api('GET', '/api/clientes', t);
        paso('El técnico NO ve los clientes', tecClientes.status === 403);
        const tecNombres = await api('GET', '/api/clientes/nombres', t);
        paso('El técnico NO ve los nombres de las empresas', tecNombres.status === 403);
        const sinTokenLista = await api('GET', '/api/solicitudes-presupuesto', null);
        paso('La bandeja exige estar logueado', sinTokenLista.status === 401);

        // --- Bandeja (la maneja Comercial) ---
        const lista = await api('GET', '/api/solicitudes-presupuesto?estado=abiertas', c);
        const mias = lista.datos.filter((x) => x.empresa === empresaA);
        paso('Comercial ve las notas abiertas de la empresa', lista.status === 200 && mias.length === 3, `${mias.length} notas`);
        const a = mias.find((x) => x.id === n1.datos.id);
        paso('La nota muestra empresa, técnico, texto limpio, cantidad y foto',
            a && a.tecnico === 'Tecnico Comercial' && a.descripcion === 'Falta extintor ABC 5 kg' && a.cantidad === 2 && a.tiene_foto === true && a.estado === 'Nueva' && a.orden_id === ordenId);
        const empresaId = a.empresa_id;
        const porEmpresa = await api('GET', `/api/solicitudes-presupuesto?empresaId=${empresaId}`, duena);
        paso('Se puede filtrar por empresa', porEmpresa.status === 200 && porEmpresa.datos.length === 3);
        const estadoMalo = await api('GET', '/api/solicitudes-presupuesto?estado=Raro', c);
        paso('Un estado inválido da error claro', estadoMalo.status === 400);

        const foto = await api('GET', `/api/solicitudes-presupuesto/${a.id}/foto`, c);
        paso('Comercial puede ver la foto', foto.status === 200 && foto.tipo.includes('image/png') && Buffer.isBuffer(foto.datos) && foto.datos.length > 50);
        const sinFotoPedida = await api('GET', `/api/solicitudes-presupuesto/${sinFoto.datos.id}/foto`, c);
        paso('Pedir la foto de una nota sin foto da 404', sinFotoPedida.status === 404);

        const enPres = await api('PUT', `/api/solicitudes-presupuesto/${a.id}`, c, { estado: 'En presupuesto', nota: 'Pedir precio al proveedor' });
        paso('Comercial pasa la nota a "En presupuesto" con una nota', enPres.status === 200 && enPres.datos.estado === 'En presupuesto' && enPres.datos.nota_comercial === 'Pedir precio al proveedor');
        const editar = await api('PUT', `/api/solicitudes-presupuesto/${a.id}`, duena, { descripcion: 'Extintor ABC 10 kg', cantidad: 4 });
        paso('Se puede corregir la descripción y la cantidad', editar.status === 200 && editar.datos.descripcion === 'Extintor ABC 10 kg' && editar.datos.cantidad === 4 && editar.datos.estado === 'En presupuesto');
        const estadoInv = await api('PUT', `/api/solicitudes-presupuesto/${a.id}`, c, { estado: 'Inventado' });
        paso('Rechaza un estado inventado', estadoInv.status === 400);
        const nada = await api('PUT', `/api/solicitudes-presupuesto/${a.id}`, c, {});
        paso('Rechaza un cambio vacío', nada.status === 400);
        const noExiste = await api('PUT', '/api/solicitudes-presupuesto/99999999', c, { estado: 'Descartada' });
        paso('Cambiar una nota inexistente da 404', noExiste.status === 404);
        const descartar = await api('PUT', `/api/solicitudes-presupuesto/${sinOrden.datos.id}`, c, { estado: 'Descartada' });
        paso('Se puede descartar una nota', descartar.status === 200 && descartar.datos.estado === 'Descartada');
        const abiertas = await api('GET', '/api/solicitudes-presupuesto?estado=abiertas', c);
        paso('Lo descartado sale de las abiertas', abiertas.datos.filter((x) => x.empresa === empresaA).length === 2);
        const resumen = await api('GET', '/api/solicitudes-presupuesto/resumen', c);
        paso('El resumen cuenta por estado', resumen.status === 200 && resumen.datos.nuevas >= 1 && resumen.datos.en_presupuesto >= 1 && resumen.datos.descartadas >= 1, JSON.stringify(resumen.datos));

        // --- Se borra la orden y el técnico: las notas se conservan ---
        await api('DELETE', `/api/ordenes/${ordenId}`, adm);
        const tras = await api('GET', `/api/solicitudes-presupuesto?empresaId=${empresaId}`, c);
        paso('Si se borra la orden, la nota queda (sin orden)', tras.datos.length === 3 && tras.datos.every((x) => x.orden_id === null));
        const delTec = await api('DELETE', `/api/tecnicos/${tecnicoId}`, adm);
        paso('Se puede eliminar un técnico que tiene notas', delTec.status === 200);
        const trasTec = await api('GET', `/api/solicitudes-presupuesto?empresaId=${empresaId}`, c);
        paso('Si se elimina el técnico, la nota conserva su nombre', trasTec.datos.length === 3 && trasTec.datos.every((x) => x.tecnico === 'Tecnico Comercial'));

        // --- Clientes (los maneja Comercial) ---
        const lista0 = await api('GET', '/api/clientes', c);
        const fichaA = (lista0.datos || []).find((x) => x.id === empresaId);
        paso('La empresa de la orden aparece en Clientes con su cantidad por presupuestar', lista0.status === 200 && fichaA && fichaA.por_presupuestar === 2, fichaA && JSON.stringify(fichaA));

        const nombreB = `Cliente Prueba Comercial ${marca} SA`;
        const cuitOk = '30-71234567-1';
        const nuevo = await api('POST', '/api/clientes', c, { razon_social: `  ${nombreB}  `, contacto: 'Laura Gómez', telefono: '351 555-0000', email: 'LAURA@EMPRESA.COM', cuit: '30712345671', direccion_principal: 'Av. Siempre Viva 742', notas: 'Paga a 30 días' });
        paso('Comercial crea un cliente (CUIT con formato, correo en minúsculas)', nuevo.status === 200 && nuevo.datos.razon_social === nombreB && nuevo.datos.cuit === cuitOk && nuevo.datos.email === 'laura@empresa.com', nuevo.datos && JSON.stringify(nuevo.datos));
        const idB = nuevo.datos.id;
        const dup = await api('POST', '/api/clientes', duena, { razon_social: nombreB.toUpperCase() });
        paso('No deja crear dos clientes con el mismo nombre (sin importar mayúsculas)', dup.status === 409, dup.datos && dup.datos.error);
        const cuitMal = await api('POST', '/api/clientes', c, { razon_social: `${nombreB} 2`, cuit: '30-71234567-2' });
        paso('Rechaza un CUIT inválido', cuitMal.status === 400, cuitMal.datos && cuitMal.datos.error);
        const cuitCorto = await api('POST', '/api/clientes', c, { razon_social: `${nombreB} 2`, cuit: '123' });
        paso('Rechaza un CUIT con pocos números', cuitCorto.status === 400);
        const mailMal = await api('POST', '/api/clientes', c, { razon_social: `${nombreB} 2`, email: 'sin-arroba' });
        paso('Rechaza un correo inválido', mailMal.status === 400);
        const sinNombre = await api('POST', '/api/clientes', c, { razon_social: ' ' });
        paso('Rechaza un cliente sin nombre', sinNombre.status === 400);

        // Datos que usa el presupuestador: actividad, riesgo (R1-R7), categoría (A/B/C) y ubicación.
        const riesgoMal = await api('PUT', `/api/clientes/${idB}`, c, { razon_social: nombreB, riesgo: 'R9' });
        paso('Rechaza un riesgo fuera de R1 a R7', riesgoMal.status === 400, riesgoMal.datos && riesgoMal.datos.error);
        const categoriaMal = await api('PUT', `/api/clientes/${idB}`, c, { razon_social: nombreB, categoria: 'Z' });
        paso('Rechaza una categoría que no es A, B ni C', categoriaMal.status === 400, categoriaMal.datos && categoriaMal.datos.error);
        const ubicacion = await api('PUT', `/api/clientes/${idB}`, c, {
            razon_social: nombreB, actividad: 'Minería', riesgo: 'r3', categoria: 'b',
            provincia: 'Córdoba', departamento: 'Punilla', ciudad: 'Cosquín',
        });
        paso(
            'Guarda actividad, riesgo, categoría y ubicación (riesgo y categoría quedan en mayúsculas)',
            ubicacion.status === 200 && ubicacion.datos.actividad === 'Minería' && ubicacion.datos.riesgo === 'R3' && ubicacion.datos.categoria === 'B'
                && ubicacion.datos.provincia === 'Córdoba' && ubicacion.datos.departamento === 'Punilla' && ubicacion.datos.ciudad === 'Cosquín',
            ubicacion.datos && JSON.stringify(ubicacion.datos)
        );
        const ubicacionLarga = await api('PUT', `/api/clientes/${idB}`, c, { razon_social: nombreB, ciudad: 'x'.repeat(101) });
        paso('Rechaza una ciudad demasiado larga', ubicacionLarga.status === 400);

        const edit = await api('PUT', `/api/clientes/${idB}`, c, { razon_social: nombreB, contacto: 'Laura G.', telefono: '', email: '', cuit: '', direccion_principal: 'Otra 1', notas: '' });
        paso('Se editan los datos y los campos vacíos se limpian', edit.status === 200 && edit.datos.contacto === 'Laura G.' && edit.datos.telefono === null && edit.datos.cuit === null && edit.datos.email === null && edit.datos.actividad === null && edit.datos.riesgo === null && edit.datos.categoria === null && edit.datos.provincia === null);
        const editDup = await api('PUT', `/api/clientes/${idB}`, c, { razon_social: empresaA });
        paso('No deja renombrar a un nombre que ya existe', editDup.status === 409);
        const editNo = await api('PUT', '/api/clientes/99999999', c, { razon_social: 'Fantasma SA' });
        paso('Editar un cliente inexistente da 404', editNo.status === 404);

        // Una orden escrita después con el mismo nombre (otras mayúsculas) usa la misma empresa.
        const ordenB = await api('POST', '/api/ordenes', adm, { tecnico_id: null, nombre_cliente: nombreB.toLowerCase(), direccion_trabajo: 'X', descripcion_tarea: 'Y' });
        paso('Una orden con el mismo nombre usa la empresa ya cargada', ordenB.status === 200 && ordenB.datos.empresa_id === idB, `empresa ${ordenB.datos && ordenB.datos.empresa_id} vs ${idB}`);
        const ordenBId = ordenB.datos.id;
        const listaFinal = await api('GET', '/api/clientes', duena);
        const fichaB = listaFinal.datos.find((x) => x.id === idB);
        paso('La ficha cuenta sus órdenes', fichaB && fichaB.ordenes === 1);
        if (ordenBId) await api('DELETE', `/api/ordenes/${ordenBId}`, adm);

        // --- Borrar usuarios: la sesión de una cuenta borrada deja de servir en el acto ---
        const delCom = await api('DELETE', `/api/admin/admins/${comId}`, duena);
        paso('Comercial puede eliminar a otro usuario', delCom.status === 200);
        const sesionMuerta = await api('GET', '/api/admin/yo', c);
        paso('Con la cuenta eliminada, /api/admin/yo ya no la reconoce', sesionMuerta.status === 401);
        const sesionMuertaTec = await api('GET', '/api/tecnicos', c);
        paso('Con la cuenta eliminada, su sesión abierta ya no sirve para nada', sesionMuertaTec.status === 401, `status ${sesionMuertaTec.status}`);
        const delYo = await api('DELETE', `/api/admin/admins/${duenaId}`, duena);
        paso('Nadie puede eliminarse a sí mismo (siempre queda un usuario Comercial)', delYo.status === 400, delYo.datos && delYo.datos.error);
    } catch (error) {
        paso('Error inesperado', false, error.stack || error.message);
    } finally {
        try {
            await pool.query("DELETE FROM solicitudes_presupuesto WHERE id_cliente LIKE 'prueba-comercial-%'");
            await pool.query("DELETE FROM ordenes WHERE empresa_id IN (SELECT id FROM empresas WHERE razon_social LIKE 'Cliente Prueba Comercial %')");
            await pool.query("DELETE FROM empresas WHERE razon_social LIKE 'Cliente Prueba Comercial %'");
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
