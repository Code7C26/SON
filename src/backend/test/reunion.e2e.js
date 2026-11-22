// Prueba de lo que pidieron los técnicos en la reunión de noviembre de 2026: firma y sello del técnico,
// recorrido desde donde está, rango horario, tareas fijas por empresa, gastos, vencimientos, estado de
// los presupuestos para el técnico, acceso del cliente y CRM comercial.
// Uso, con el backend prendido: node test/reunion.e2e.js   (PRUEBA_URL=http://127.0.0.1:3999 para otro puerto)
require('dotenv').config();
const { Pool } = require('pg');

const BASE = process.env.PRUEBA_URL || `http://127.0.0.1:${process.env.PORT || 3000}`;
const pool = new Pool({
    user: process.env.DB_USER, host: process.env.DB_HOST, database: process.env.DB_NAME,
    password: process.env.DB_PASSWORD, port: Number(process.env.DB_PORT || 5432),
});
const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

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
    const tipo = res.headers.get('content-type') || '';
    const datos = tipo.includes('application/json') ? await res.json() : await res.text();
    return { status: res.status, datos };
}

(async () => {
    const marca = Date.now();
    const cliente = `Cliente Reunion ${marca}`;
    const creado = { tecnico: null, ordenes: [], empresa: null };
    try {
        const login = await api('POST', '/api/admin/login', null, { email: process.env.ADMIN_EMAIL, password: process.env.ADMIN_PASSWORD });
        const token = login.datos && login.datos.token;
        paso('Ingresa el administrador', login.status === 200 && token);

        // --- Perfil del técnico: salida, matrícula, firma con sello ---
        const mala = await api('POST', '/api/tecnicos', token, { nombre: 'Tec Reunion', email: `mala.${marca}@son.test`, password: 'Prueba123', firma_sello: 'data:text/plain;base64,aG9sYQ==' });
        paso('Una firma que no es imagen se rechaza', mala.status === 400);
        const email = `reunion.${marca}@son.test`;
        const alta = await api('POST', '/api/tecnicos', token, {
            nombre: 'Tec Reunion', email, password: 'Prueba123',
            salida_direccion: 'Villa María, Córdoba', matricula: 'HyS-1234', firma_sello: PNG,
        });
        creado.tecnico = alta.datos && alta.datos.id;
        paso('Se registra el técnico con su perfil', alta.status === 200 && creado.tecnico);
        const lista = await api('GET', '/api/tecnicos', token);
        const fila = Array.isArray(lista.datos) && lista.datos.find((t) => t.id === creado.tecnico);
        paso('El panel ve la salida, la matrícula y que tiene firma', fila && fila.salida_direccion === 'Villa María, Córdoba' && fila.matricula === 'HyS-1234' && fila.tiene_firma === true);
        const sinCambio = await api('PUT', `/api/tecnicos/${creado.tecnico}`, token, { nombre: 'Tec Reunion', email });
        const despues = await api('GET', '/api/tecnicos', token);
        const igual = despues.datos.find((t) => t.id === creado.tecnico);
        paso('Editar sin mandar el perfil no lo borra', sinCambio.status === 200 && igual.tiene_firma === true && igual.matricula === 'HyS-1234');

        const loginTec = await api('POST', '/api/tecnicos/login', null, { email, password: 'Prueba123' });
        const tokenTec = loginTec.datos && loginTec.datos.token;
        paso('Ingresa el técnico', loginTec.status === 200 && tokenTec);
        const yo = await api('GET', '/api/tecnicos/yo', tokenTec);
        paso('La app sabe que el técnico ya tiene firma cargada', yo.status === 200 && yo.datos.tiene_firma === true);

        // --- Tareas fijas de la empresa y rango horario ---
        const hoy = new Date();
        const dia = `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-${String(hoy.getDate()).padStart(2, '0')}`;
        const malHorario = await api('POST', '/api/ordenes', token, {
            tecnico_id: creado.tecnico, nombre_cliente: cliente, direccion_trabajo: 'Av. Colón 100, Córdoba',
            fecha_asignada: dia, hora_ejecucion: '12:00', hora_hasta: '09:00',
        });
        paso('Un rango horario al revés se rechaza', malHorario.status === 400);
        const primera = await api('POST', '/api/ordenes', token, {
            tecnico_id: creado.tecnico, nombre_cliente: cliente, direccion_trabajo: 'Av. Colón 100, Córdoba',
            fecha_asignada: dia, hora_ejecucion: '08:00', hora_hasta: '12:00',
            puntos: ['Control de extintores', 'Recorrida de depósito'], guardar_tareas_fijas: true,
        });
        if (primera.datos && primera.datos.id) creado.ordenes.push(primera.datos.id);
        creado.empresa = primera.datos && primera.datos.empresa_id;
        paso('Se crea la orden con rango horario', primera.status === 200 && String(primera.datos.hora_hasta).startsWith('12:00'));
        const tareas = await api('GET', `/api/clientes/tareas?nombre=${encodeURIComponent(cliente)}`, token);
        paso('Las tareas quedan como fijas de la empresa', tareas.status === 200 && tareas.datos.tareas.length === 2);
        const segunda = await api('POST', '/api/ordenes', token, {
            tecnico_id: creado.tecnico, nombre_cliente: cliente, direccion_trabajo: 'Av. Colón 100, Córdoba', fecha_asignada: dia,
        });
        if (segunda.datos && segunda.datos.id) creado.ordenes.push(segunda.datos.id);
        paso('Una orden nueva sin checklist arranca con las tareas fijas', segunda.status === 200 && Array.isArray(segunda.datos.puntos) && segunda.datos.puntos.length === 2);

        const deTec = await api('GET', `/api/ordenes/tecnico/${creado.tecnico}`, tokenTec);
        const vista = Array.isArray(deTec.datos) && deTec.datos.find((o) => o.id === creado.ordenes[0]);
        paso('El técnico ve el rango horario', vista && vista.hora === '08:00' && vista.hora_hasta === '12:00');

        const recorrido = await api('POST', '/api/ordenes/recorrido', tokenTec, { lat: -31.4135, lng: -64.1811 });
        paso('Ordena el recorrido de hoy desde donde está el técnico', recorrido.status === 200 && Array.isArray(recorrido.datos.ordenes) && recorrido.datos.desde, JSON.stringify(recorrido.datos).slice(0, 120));

        const camino = await api('POST', `/api/ordenes/${creado.ordenes[0]}/en-camino`, tokenTec, {});
        paso('Avisar "en camino" responde aunque el cliente no tenga correo', camino.status === 200);

        // --- Gastos ---
        const gastoId = `g${marca}abc`;
        const gasto = await api('POST', '/api/gastos', tokenTec, { idCliente: gastoId, ordenId: creado.ordenes[0], vehiculo: 'Clio', kmInicio: 1000, kmFin: 1080, tipo: 'Combustible', monto: '50000,50', foto: PNG });
        paso('El técnico carga un gasto con foto', gasto.status === 200 && gasto.datos.id);
        const repetido = await api('POST', '/api/gastos', tokenTec, { idCliente: gastoId, tipo: 'Combustible', monto: 1 });
        paso('Si el celular reenvía el gasto no se duplica', repetido.status === 200 && repetido.datos.yaExistia === true);
        const kmMal = await api('POST', '/api/gastos', tokenTec, { idCliente: `g${marca}mal`, kmInicio: 100, kmFin: 50 });
        paso('Kilometraje final menor que el inicial se rechaza', kmMal.status === 400);
        const gastos = await api('GET', `/api/gastos?tecnicoId=${creado.tecnico}`, token);
        const g = gastos.datos && gastos.datos.gastos && gastos.datos.gastos.find((item) => item.id === gasto.datos.id);
        paso('Administración ve el gasto con la empresa de la orden', g && g.empresa === cliente && g.monto === 50000.5 && g.tiene_foto === true);
        const revisado = await api('PUT', `/api/gastos/${gasto.datos.id}`, token, { revisado: true });
        paso('Se marca como revisado', revisado.status === 200 && revisado.datos.revisado === true);
        const planilla = await api('GET', `/api/gastos/planilla?tecnicoId=${creado.tecnico}`, token);
        paso('La planilla de gastos sale para Excel', planilla.status === 200 && String(planilla.datos).includes('Combustible') && String(planilla.datos).includes(';80;'));

        // --- Vencimientos ---
        const enUnMes = new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10);
        const venc = await api('POST', '/api/vencimientos', tokenTec, { idCliente: `v${marca}abc`, ordenId: creado.ordenes[0], descripcion: 'Extintor ABC 5 kg', cantidad: 3, vence: enUnMes });
        paso('El técnico anota un vencimiento', venc.status === 200 && venc.datos.id);
        const mios = await api('GET', '/api/vencimientos/mios', tokenTec);
        paso('El técnico ve el vencimiento de su cliente', Array.isArray(mios.datos) && mios.datos.some((v) => v.id === venc.datos.id && v.dias >= 29));
        const panelVenc = await api('GET', '/api/vencimientos', token);
        paso('El panel ve el vencimiento', panelVenc.status === 200 && panelVenc.datos.vencimientos.some((v) => v.id === venc.datos.id && v.empresa === cliente));
        const resuelto = await api('PUT', `/api/vencimientos/${venc.datos.id}`, token, { resuelto: true });
        paso('Se marca como resuelto', resuelto.status === 200 && resuelto.datos.resuelto === true);

        // --- Presupuesto pedido por el técnico ---
        const nota = await api('POST', '/api/solicitudes-presupuesto', tokenTec, { idCliente: `s${marca}abc`, ordenId: creado.ordenes[0], descripcion: 'Cartel de salida', cantidad: 2 });
        paso('El técnico anota algo para presupuestar', nota.status === 200);
        let mias = await api('GET', '/api/solicitudes-presupuesto/mias', tokenTec);
        let mia = Array.isArray(mias.datos) && mias.datos.find((s) => s.id === nota.datos.id);
        paso('Lo ve como "Pedido"', mia && mia.estado_visible === 'Pedido');
        await api('PUT', `/api/solicitudes-presupuesto/${nota.datos.id}`, token, { estado: 'Enviada' });
        mias = await api('GET', '/api/solicitudes-presupuesto/mias', tokenTec);
        mia = mias.datos.find((s) => s.id === nota.datos.id);
        paso('Cuando comercial lo envía, el técnico lo ve "Enviado"', mia && mia.estado_visible === 'Enviado');
        await pool.query('DELETE FROM solicitudes_presupuesto WHERE id = $1', [nota.datos.id]);

        // --- Informe con firma cargada y acceso del cliente ---
        const informe = await api('POST', '/api/generar-informe', tokenTec, {
            ordenId: creado.ordenes[0], cliente, direccion: 'Av. Colón 100, Córdoba', comentarios: 'Todo en orden',
            checklist: [{ tarea: 'Control de extintores', hecho: true }], firmaCliente: PNG,
            inicio: new Date(Date.now() - 3600000).toISOString(), fin: new Date().toISOString(), sinPdf: true,
        });
        paso('Se genera el informe sin que el técnico firme en el celular', informe.status === 200 && informe.datos.ok);
        const tokenInforme = await pool.query('SELECT token_informe FROM ordenes WHERE id = $1', [creado.ordenes[0]]);
        paso('El informe queda enlazado a la orden aunque el cliente no tenga correo', Boolean(tokenInforme.rows[0] && tokenInforme.rows[0].token_informe));

        const activar = await api('POST', `/api/clientes/${creado.empresa}/portal`, token, { activo: true });
        paso('Se activa el acceso del cliente', activar.status === 200 && activar.datos.activo && /\/cliente\/[a-f0-9]{48}$/.test(activar.datos.enlace));
        const ruta = activar.datos.enlace.replace(/^https?:\/\/[^/]+/, '');
        const pagina = await api('GET', ruta, null);
        paso('El cliente ve su página con el informe', pagina.status === 200 && pagina.datos.includes(cliente) && pagina.datos.includes('Ver informe'));
        const pdf = await fetch(BASE + `/informe/${tokenInforme.rows[0].token_informe}`);
        paso('El informe se descarga desde el enlace', pdf.status === 200 && (pdf.headers.get('content-type') || '').includes('pdf'));
        await api('POST', `/api/clientes/${creado.empresa}/portal`, token, { activo: false });
        const cortado = await api('GET', ruta, null);
        paso('Con el acceso desactivado el enlace deja de abrir', cortado.status === 404);

        // Administración (sin acceso a lo comercial) también maneja el acceso, desde Informes.
        const emailAdmin = `admin.${marca}@son.test`;
        const altaAdmin = await api('POST', '/api/admin/admins', token, { nombre: 'Administración prueba', email: emailAdmin, password: 'Prueba123', rol: 'admin' });
        creado.admin = altaAdmin.datos && altaAdmin.datos.id;
        const loginAdmin = await api('POST', '/api/admin/login', null, { email: emailAdmin, password: 'Prueba123' });
        const tokenAdmin = loginAdmin.datos && loginAdmin.datos.token;
        const sinComercial = await api('GET', '/api/clientes', tokenAdmin);
        paso('Administración no ve las fichas comerciales', sinComercial.status === 403);
        const porCarpeta = await api('GET', `/api/clientes/portal-por-nombre?nombre=${encodeURIComponent(cliente.replace(/ /g, '_'))}`, tokenAdmin);
        paso('Administración encuentra al cliente por el nombre de su carpeta', porCarpeta.status === 200 && porCarpeta.datos.id === creado.empresa);
        const activaAdmin = await api('POST', `/api/clientes/${creado.empresa}/portal`, tokenAdmin, { activo: true });
        paso('Administración activa el acceso del cliente', activaAdmin.status === 200 && activaAdmin.datos.activo === true);
        await api('POST', `/api/clientes/${creado.empresa}/portal`, tokenAdmin, { activo: false });
        const noExiste = await api('GET', '/api/clientes/portal-por-nombre?nombre=Nadie%20Inventado', tokenAdmin);
        paso('Un cliente que no está en el sistema da un aviso claro', noExiste.status === 404);

        // --- CRM ---
        const config = await api('GET', '/api/crm/config', token);
        paso('El CRM tiene su configuración', config.status === 200 && config.datos.umbrales.Prospecto === 7);
        await api('PUT', `/api/crm/clientes/${creado.empresa}`, token, { tipo_cliente: 'Prospecto' });
        const contacto = await api('POST', '/api/crm/notas', token, {
            empresaId: creado.empresa, tipo: 'Llamada', texto: 'Pide cotizar mediciones', pendiente: 'Enviar presupuesto', pendienteFecha: dia,
        });
        paso('Se anota un contacto con un pendiente', contacto.status === 200 && contacto.datos.pendiente === 'Enviar presupuesto');
        const clientes = await api('GET', '/api/crm/clientes', token);
        const ficha = Array.isArray(clientes.datos) && clientes.datos.find((c) => c.id === creado.empresa);
        paso('El cliente queda al día (verde) y con un pendiente', ficha && ficha.alerta.estado === 'verde' && ficha.pendientes === 1);
        const pendientes = await api('GET', '/api/crm/pendientes', token);
        paso('El pendiente aparece en la lista', pendientes.status === 200 && pendientes.datos.some((n) => n.id === contacto.datos.id));
        const hecho = await api('PUT', `/api/crm/notas/${contacto.datos.id}`, token, { pendienteHecho: true });
        paso('Se tilda el pendiente sin perder la nota', hecho.status === 200 && hecho.datos.pendiente_hecho === true && hecho.datos.texto === 'Pide cotizar mediciones');
        const conversion = await api('GET', '/api/crm/conversion', token);
        paso('Se calcula la conversión', conversion.status === 200 && typeof conversion.datos.enviados === 'number');
        const bitacora = await api('GET', '/api/crm/planilla?tipo=bitacora', token);
        paso('La bitácora sale para Excel', bitacora.status === 200 && String(bitacora.datos).includes('Pide cotizar mediciones'));
    } catch (error) {
        paso('La prueba terminó sin un error inesperado', false, error.stack);
    } finally {
        if (creado.empresa) {
            await pool.query('DELETE FROM gastos WHERE tecnico_id = $1', [creado.tecnico]).catch(() => {});
            await pool.query('DELETE FROM vencimientos WHERE empresa_id = $1', [creado.empresa]).catch(() => {});
            await pool.query('DELETE FROM crm_notas WHERE empresa_id = $1', [creado.empresa]).catch(() => {});
        }
        for (const id of creado.ordenes) {
            await pool.query('DELETE FROM visitas WHERE orden_id = $1', [id]).catch(() => {});
            await pool.query('DELETE FROM encuestas WHERE orden_id = $1', [id]).catch(() => {});
            await pool.query('DELETE FROM ordenes WHERE id = $1', [id]).catch(() => {});
        }
        await pool.query('DELETE FROM empresas WHERE razon_social = $1', [cliente]).catch(() => {});
        if (creado.tecnico) await pool.query('DELETE FROM tecnicos WHERE id = $1', [creado.tecnico]).catch(() => {});
        if (creado.admin) await pool.query('DELETE FROM admins WHERE id = $1', [creado.admin]).catch(() => {});
        await pool.end();
        console.log(fallos ? `RESULTADO: ${fallos} fallas` : 'RESULTADO: todo OK');
        process.exit(fallos ? 1 : 0);
    }
})();
