// Prueba del presupuestador (tarifario, inflación, costos, presupuestos y PDF)
// contra el servidor que está corriendo. Solo Comercial puede usar estas rutas.
// Uso, con el backend prendido:   node test/presupuestos.e2e.js
// Crea datos temporales (@son.test, "Cliente Prueba Presupuesto ...") y los borra al terminar.
require('dotenv').config();
const { Pool } = require('pg');
const { asegurarAdmin } = require('../src/auth');

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
    const tipo = res.headers.get('content-type') || '';
    if (tipo.includes('application/json')) {
        try { datos = await res.json(); } catch { /* sin cuerpo */ }
    } else {
        datos = Buffer.from(await res.arrayBuffer());
    }
    return { status: res.status, datos, tipo, headers: res.headers };
}

(async () => {
    const marca = Date.now();
    const nombreCliente = `Cliente Prueba Presupuesto ${marca}`;
    const familiaPrueba = `Prueba ${marca}`;
    const conceptoCosto = `Hora prueba ${marca}`;
    const mesManual = '2099-01';
    let numeroOriginal = null;
    let tarifaId = null;
    let costoId = null;
    let empresaId = null;
    let presupuestoId = null;
    let borradorId = null;
    let solicitudId = null;
    let comId = null;
    let admId = null;
    try {
        const login = await api('POST', '/api/admin/login', null, { email: ADMIN_EMAIL, password: ADMIN_PASSWORD });
        paso('La cuenta principal ingresa (tipo Comercial)', login.status === 200 && login.datos.rol === 'comercial', `rol=${login.datos && login.datos.rol}`);
        if (login.status !== 200) throw new Error('No se pudo ingresar con las credenciales del .env');
        const duena = login.datos.token;

        const emailCom = `comercial.pre.${marca}@son.test`;
        const emailAdm = `administracion.pre.${marca}@son.test`;
        const com = await api('POST', '/api/admin/admins', duena, { nombre: 'Comercial Presupuesto', email: emailCom, password: 'Prueba123', rol: 'comercial' });
        paso('Crea un usuario Comercial', com.status === 200);
        comId = com.datos.id;
        const adm0 = await api('POST', '/api/admin/admins', duena, { nombre: 'Administracion Presupuesto', email: emailAdm, password: 'Prueba123', rol: 'admin' });
        paso('Crea un usuario de Administración', adm0.status === 200);
        admId = adm0.datos.id;
        const lc = await api('POST', '/api/admin/login', null, { email: emailCom, password: 'Prueba123' });
        const c = lc.datos.token;
        const la = await api('POST', '/api/admin/login', null, { email: emailAdm, password: 'Prueba123' });
        const adm = la.datos.token;

        for (const [metodo, ruta, etiqueta, cuerpo] of [
            ['GET', '/api/presupuestos', 'Administración NO ve los presupuestos'],
            ['POST', '/api/presupuestos/calcular', 'Administración NO puede calcular un presupuesto', { cliente: { razonSocial: 'X' }, items: [] }],
            ['GET', '/api/tarifas', 'Administración NO ve el tarifario'],
            ['GET', '/api/costos', 'Administración NO ve los costos'],
            ['GET', '/api/ipc', 'Administración NO ve la inflación'],
            ['GET', '/api/comercial/config', 'Administración NO ve los parámetros comerciales'],
            ['PUT', '/api/presupuestos/1/seguimiento', 'Administración NO puede cargar el seguimiento', { prioridad: 'alta' }],
        ]) {
            const r = await api(metodo, ruta, adm, cuerpo);
            paso(etiqueta, r.status === 403, `status ${r.status}`);
        }
        const sinToken = await api('GET', '/api/presupuestos', null);
        paso('Los presupuestos exigen estar logueado', sinToken.status === 401);

        const ipc = await api('GET', '/api/ipc', c);
        paso(
            'Comercial ve la inflación traída del INDEC',
            ipc.status === 200 && Array.isArray(ipc.datos.meses) && ipc.datos.meses.length > 0
                && ipc.datos.meses.some((m) => m.mes === '2026-07' && m.fuente === 'INDEC'),
            ipc.status !== 200 ? `status ${ipc.status}` : `meses=${ipc.datos.meses && ipc.datos.meses.length}`
        );

        const manual = await api('PUT', `/api/ipc/${mesManual}`, c, { porcentaje: '2,1' });
        paso('Se puede cargar un mes a mano (también con coma)', manual.status === 200 && manual.datos.porcentaje === 2.1 && manual.datos.fuente === 'Manual');
        const ipc2 = await api('GET', '/api/ipc', c);
        const filaManual = ipc2.datos.meses.find((m) => m.mes === mesManual);
        paso('El mes cargado a mano aparece en la lista', !!filaManual && filaManual.fuente === 'Manual' && filaManual.porcentaje === 2.1);
        const borrarMes = await api('DELETE', `/api/ipc/${mesManual}`, c);
        paso('Se puede borrar un mes de inflación', borrarMes.status === 200);
        const mesInvalido = await api('PUT', '/api/ipc/2026-13', c, { porcentaje: 2 });
        paso('Rechaza un mes que no existe', mesInvalido.status === 400);

        const tarifas = await api('GET', '/api/tarifas?mes=2026-09', c);
        paso('Comercial ve el tarifario CIEC (61 filas)', tarifas.status === 200 && Array.isArray(tarifas.datos.tarifas) && tarifas.datos.tarifas.length === 61, `cantidad=${tarifas.datos && tarifas.datos.tarifas && tarifas.datos.tarifas.length}`);
        const hys = (tarifas.datos.tarifas || []).find((t) => t.tramo === '1 a 15 trabajadores' && /excepto construcci/i.test(t.servicio));
        paso(
            'La tarifa de HyS 1 a 15 trabajadores tiene precio actualizado a septiembre (más que el de enero)',
            !!hys && hys.valorBase === 430000 && typeof hys.valorActual === 'number' && hys.valorActual > 430000,
            hys ? `base=${hys.valorBase} actual=${hys.valorActual}` : 'no está'
        );
        const tarifaCiecId = hys && hys.id;
        const precioHys = hys && hys.valorActual;

        const config = await api('GET', '/api/comercial/config', c);
        paso('Los parámetros comerciales están cargados (IVA 21 %, próximo número listo)', config.status === 200 && config.datos.iva === 21 && Number.isInteger(config.datos.proximoNumero) && config.datos.proximoNumero >= 3612, JSON.stringify(config.datos && { iva: config.datos.iva, n: config.datos.proximoNumero }));
        numeroOriginal = config.datos.proximoNumero;

        const tarifaNueva = await api('POST', '/api/tarifas', c, {
            familia: familiaPrueba, servicio: 'Servicio de prueba', tramo: 'único', valorBase: 100000, mesBase: '2026-01', indexa: true,
        });
        paso('Se puede crear una tarifa propia', tarifaNueva.status === 200 && tarifaNueva.datos.familia === familiaPrueba && tarifaNueva.datos.valorBase === 100000);
        tarifaId = tarifaNueva.datos.id;
        const tarifaDup = await api('POST', '/api/tarifas', c, { familia: familiaPrueba, servicio: 'Servicio de prueba', tramo: 'único', valorBase: 1, mesBase: '2026-01' });
        paso('No deja dos tarifas iguales', tarifaDup.status === 409);
        const tarifaEdit = await api('PUT', `/api/tarifas/${tarifaId}`, c, {
            familia: familiaPrueba, servicio: 'Servicio de prueba', tramo: 'único', valorBase: 120000, mesBase: '2026-01', indexa: false,
        });
        paso('Se edita una tarifa (sin indexar queda el valor base)', tarifaEdit.status === 200 && tarifaEdit.datos.valorActual === 120000 && tarifaEdit.datos.indexa === false);

        const costoNuevo = await api('POST', '/api/costos', c, { concepto: conceptoCosto, unidad: 'hora', valorBase: 40000, mesBase: '2026-01', indexa: false });
        paso('Se puede crear un costo interno', costoNuevo.status === 200 && costoNuevo.datos.valorActual === 40000);
        costoId = costoNuevo.datos.id;

        const cliente = await api('POST', '/api/clientes', c, {
            razon_social: nombreCliente, contacto: 'Laura Gómez', telefono: '351 555-0000',
            email: 'laura@empresa.com', cuit: '30712345671', direccion_principal: 'Av. Siempre Viva 742',
            provincia: 'Córdoba', ciudad: 'Córdoba',
        });
        paso('Comercial crea el cliente del presupuesto', cliente.status === 200);
        empresaId = cliente.datos.id;

        const solicitud = await pool.query(
            `INSERT INTO solicitudes_presupuesto (id_cliente, empresa_id, empresa_nombre, descripcion, cantidad, estado)
             VALUES ($1, $2, $3, 'Falta extintor ABC 5 kg', 2, 'Nueva') RETURNING id`,
            [`prueba-presupuesto-${marca}`, empresaId, nombreCliente]
        );
        solicitudId = solicitud.rows[0].id;

        const cuerpoBase = {
            empresaId,
            cliente: { atencion: 'Ing. Valentina Pérez' },
            fecha: '2026-09-15',
            bonificacion: 30,
            items: [
                { tarifaId: tarifaCiecId, descripcion: 'Servicio mensual de HyS, 1 a 15 trabajadores', periodicidad: 'mensual', bonificable: true, costeo: [{ costoId, cantidad: 8 }] },
                { descripcion: 'Extintor ABC 5 kg', cantidad: 2, precioManual: 45000, periodicidad: 'unico', bonificable: false },
            ],
            solicitudIds: [solicitudId],
            observaciones: 'Presupuesto de prueba',
        };

        const sinItems = await api('POST', '/api/presupuestos/calcular', c, { empresaId, items: [] });
        paso('Calcular acepta un presupuesto vacío (todavía se está armando)', sinItems.status === 200 && sinItems.datos.calculo.totalMensual === 0);

        const calc = await api('POST', '/api/presupuestos/calcular', c, cuerpoBase);
        const mensualEsperado = Math.round(precioHys * 0.7);
        paso('Calcular usa el precio del tarifario actualizado y aplica la bonificación', calc.status === 200 && calc.datos.calculo.totalMensual === mensualEsperado, `mensual=${calc.datos && calc.datos.calculo && calc.datos.calculo.totalMensual} esperado=${mensualEsperado}`);
        paso('El ítem suelto queda como pago único (sin bonificación)', calc.status === 200 && calc.datos.calculo.totalUnico === 90000, `unico=${calc.datos && calc.datos.calculo && calc.datos.calculo.totalUnico}`);
        const margen = calc.datos.calculo.margen;
        // 365268 / 320000 - 1 = 14,15 % → por debajo del 20 %.
        paso('Con 8 horas a 40.000 el margen queda por debajo del 20 % y avisa', calc.status === 200 && calc.datos.calculo.nivelMargen === 'bajo' && Array.isArray(calc.datos.calculo.avisos) && calc.datos.calculo.avisos.some((a) => a.tipo === 'margen_bajo'), `margen=${margen} avisos=${JSON.stringify(calc.datos && calc.datos.calculo && calc.datos.calculo.avisos)}`);

        const creado = await api('POST', '/api/presupuestos', c, cuerpoBase);
        const numero = creado.datos && creado.datos.numero;
        paso('Crea el presupuesto con el próximo número, versión 1, como borrador', creado.status === 200 && numero === numeroOriginal && creado.datos.version === 1 && creado.datos.etiqueta === String(numeroOriginal) && creado.datos.estado === 'Borrador' && creado.datos.editable === true, creado.datos && `n=${creado.datos.numero} estado=${creado.datos.estado}`);
        presupuestoId = creado.datos.id;
        paso('Completa el cliente con la ficha (nombre, domicilio, correo)', creado.status === 200 && creado.datos.cliente.razonSocial === nombreCliente && creado.datos.cliente.email === 'laura@empresa.com' && creado.datos.cliente.atencion === 'Ing. Valentina Pérez');
        paso('Las notas del técnico quedan vinculadas y pasan a "En presupuesto"', creado.status === 200 && creado.datos.solicitudIds.includes(solicitudId));
        const notaVinculada = await pool.query('SELECT estado FROM solicitudes_presupuesto WHERE id = $1', [solicitudId]);
        paso('La nota quedó en estado En presupuesto', notaVinculada.rows[0].estado === 'En presupuesto');

        const lista = await api('GET', '/api/presupuestos', c);
        paso('Aparece en la lista con el total mensual bonificado', lista.status === 200 && lista.datos.some((p) => p.id === presupuestoId && p.totalMensual === mensualEsperado && p.totalUnico === 90000));

        const edit = await api('PUT', `/api/presupuestos/${presupuestoId}`, c, {
            ...cuerpoBase,
            bonificacion: 10,
            items: [{ descripcion: 'Ítem editado a mano', precioManual: 200000, periodicidad: 'mensual' }],
        });
        paso('Se puede editar un borrador', edit.status === 200 && edit.datos.bonificacion === 10 && edit.datos.items.length === 1 && edit.datos.calculo.totalMensual === 180000);

        const enviado = await api('PUT', `/api/presupuestos/${presupuestoId}/estado`, c, { estado: 'Enviado' });
        paso('Al enviarlo deja de ser editable y anota la fecha', enviado.status === 200 && enviado.datos.estado === 'Enviado' && enviado.datos.editable === false && !!enviado.datos.fechaEnvio);
        const notaPresupuestada = await pool.query('SELECT estado FROM solicitudes_presupuesto WHERE id = $1', [solicitudId]);
        paso('Al enviarlo, la nota pasa a Presupuestada', notaPresupuestada.rows[0].estado === 'Presupuestada');

        const seg = await api('PUT', `/api/presupuestos/${presupuestoId}/seguimiento`, c, {
            prioridad: 'alta', responsable: 'Valentina', fechaLimite: '2026-11-15', notaSeguimiento: 'Llamar el lunes',
        });
        paso('Se puede cargar el seguimiento (prioridad, responsable, fecha límite)', seg.status === 200 && seg.datos.prioridad === 'alta' && seg.datos.responsable === 'Valentina' && seg.datos.fechaLimite === '2026-11-15' && seg.datos.notaSeguimiento === 'Llamar el lunes');
        const prioMala = await api('PUT', `/api/presupuestos/${presupuestoId}/seguimiento`, c, { prioridad: 'urgentisimo' });
        paso('Rechaza una prioridad inventada', prioMala.status === 400);
        const negociando = await api('PUT', `/api/presupuestos/${presupuestoId}/estado`, c, { estado: 'Negociando' });
        paso('Pasa a Negociando en el tablero', negociando.status === 200 && negociando.datos.estado === 'Negociando');
        const facturado = await api('PUT', `/api/presupuestos/${presupuestoId}/seguimiento`, c, { facturado: true });
        paso('Se puede marcar como facturado', facturado.status === 200 && facturado.datos.facturado === true);

        const editarEnviado = await api('PUT', `/api/presupuestos/${presupuestoId}`, c, cuerpoBase);
        paso('Un presupuesto enviado no se puede modificar', editarEnviado.status === 409, editarEnviado.datos && editarEnviado.datos.error);

        const borrarEnviado = await api('DELETE', `/api/presupuestos/${presupuestoId}`, c);
        paso('Un presupuesto enviado no se puede borrar', borrarEnviado.status === 409);

        const act = await api('POST', `/api/presupuestos/${presupuestoId}/actualizar`, c, { repreciar: false });
        paso(`Crear una versión "act" deja el mismo número y etiqueta "${numero} - act"`, act.status === 200 && act.datos.numero === numero && act.datos.version === 2 && act.datos.etiqueta === `${numero} - act` && act.datos.estado === 'Borrador' && act.datos.esUltimaVersion === true);
        paso('La versión act copia el responsable y la prioridad, y todavía no está facturada', act.status === 200 && act.datos.responsable === 'Valentina' && act.datos.prioridad === 'alta' && act.datos.facturado === false);
        const actId = act.datos.id;
        const estadoViejo = await api('PUT', `/api/presupuestos/${presupuestoId}/estado`, c, { estado: 'Rechazado' });
        paso('El estado se cambia en la versión más nueva, no en una anterior', estadoViejo.status === 409);

        const pdf = await api('GET', `/api/presupuestos/${actId}/pdf`, c);
        paso(
            'El PDF se abre (no se descarga) y es un archivo PDF',
            pdf.status === 200 && pdf.tipo.includes('application/pdf') && pdf.datos.slice(0, 5).toString() === '%PDF-' && String(pdf.headers.get('content-disposition') || '').includes('inline'),
            `status=${pdf.status} tipo=${pdf.tipo} disp=${pdf.headers.get('content-disposition')}`
        );

        const otro = await api('POST', '/api/presupuestos', c, {
            cliente: { razonSocial: 'Cliente suelto de prueba' },
            items: [{ descripcion: 'Algo suelto', precioManual: 1000, periodicidad: 'unico' }],
        });
        paso('Se puede armar un presupuesto sin ficha de cliente, escribiendo el nombre', otro.status === 200 && otro.datos.cliente.razonSocial === 'Cliente suelto de prueba' && otro.datos.numero === numeroOriginal + 1);
        borradorId = otro.datos.id;
        const borrado = await api('DELETE', `/api/presupuestos/${borradorId}`, c);
        paso('Un borrador sí se puede borrar', borrado.status === 200);
        const yaNo = await api('GET', `/api/presupuestos/${borradorId}`, c);
        paso('El borrador borrado ya no existe', yaNo.status === 404);
        borradorId = null;

        const filtrado = await api('GET', '/api/presupuestos?estado=Enviado', c);
        paso('Se puede filtrar la lista por estado', filtrado.status === 200 && filtrado.datos.every((p) => p.estado === 'Enviado') && !filtrado.datos.some((p) => p.id === actId));

        const sinPrecio = await api('POST', '/api/presupuestos', c, {
            cliente: { razonSocial: 'Sin precio' },
            items: [{ descripcion: 'Sin precio' }],
        });
        paso('No deja guardar un ítem sin precio', sinPrecio.status === 400, sinPrecio.datos && sinPrecio.datos.error);

        const proximo = await api('PUT', '/api/comercial/config', c, { proximoNumero: numero });
        paso('No deja bajar el próximo número por debajo de los que ya existen', proximo.status === 400);

        const borrarTarifa = await api('DELETE', `/api/tarifas/${tarifaId}`, c);
        paso('Se puede borrar una tarifa propia', borrarTarifa.status === 200);
        tarifaId = null;
        const borrarCosto = await api('DELETE', `/api/costos/${costoId}`, c);
        paso('Se puede borrar un costo interno', borrarCosto.status === 200);
        costoId = null;
    } catch (error) {
        paso('Error inesperado', false, error.stack || error.message);
    } finally {
        try {
            if (presupuestoId) await pool.query('DELETE FROM presupuestos WHERE numero IN (SELECT numero FROM presupuestos WHERE id = $1)', [presupuestoId]);
            if (borradorId) await pool.query('DELETE FROM presupuestos WHERE id = $1', [borradorId]);
            await pool.query("DELETE FROM presupuestos WHERE cliente->>'razonSocial' LIKE 'Cliente %prueba%' OR cliente->>'razonSocial' LIKE 'Cliente suelto de prueba' OR cliente->>'razonSocial' = 'Sin precio'");
            if (solicitudId) await pool.query('DELETE FROM solicitudes_presupuesto WHERE id = $1', [solicitudId]);
            await pool.query("DELETE FROM solicitudes_presupuesto WHERE id_cliente LIKE 'prueba-presupuesto-%'");
            if (empresaId) await pool.query('DELETE FROM empresas WHERE id = $1', [empresaId]);
            await pool.query("DELETE FROM empresas WHERE razon_social LIKE 'Cliente Prueba Presupuesto %'");
            if (tarifaId) await pool.query('DELETE FROM tarifas WHERE id = $1', [tarifaId]);
            await pool.query('DELETE FROM tarifas WHERE familia LIKE $1', [`Prueba %`]);
            if (costoId) await pool.query('DELETE FROM costos_internos WHERE id = $1', [costoId]);
            await pool.query('DELETE FROM costos_internos WHERE concepto LIKE $1', [`Hora prueba %`]);
            await pool.query('DELETE FROM ipc_mensual WHERE mes = $1', [mesManual]);
            if (numeroOriginal !== null) {
                await pool.query(
                    `INSERT INTO configuracion_comercial (clave, valor) VALUES ('proximo_numero', $1::jsonb)
                     ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor, actualizada_en = now()`,
                    [JSON.stringify(numeroOriginal)]
                );
            }
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
