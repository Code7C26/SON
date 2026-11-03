// Prueba del calendario, formularios, aviso al cliente, encuesta y tiempos.
// Uso, con el backend prendido: node test/campo.e2e.js
require('dotenv').config();
const { Pool } = require('pg');

const BASE = process.env.PRUEBA_URL || `http://127.0.0.1:${process.env.PORT || 3000}`;
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
    const tipo = res.headers.get('content-type') || '';
    const datos = tipo.includes('application/json') ? await res.json() : await res.text();
    return { status: res.status, datos };
}

(async () => {
    const marca = Date.now();
    const cliente = `Cliente Campo ${marca}`;
    let ordenId = null;
    let formularioId = null;
    let tecnicoId = null;
    try {
        const login = await api('POST', '/api/admin/login', null, { email: process.env.ADMIN_EMAIL, password: process.env.ADMIN_PASSWORD });
        const token = login.datos && login.datos.token;
        paso('Ingresa el administrador', login.status === 200 && token);

        const tecnicos = await api('GET', '/api/tecnicos', token);
        tecnicoId = tecnicos.datos && tecnicos.datos[0] && tecnicos.datos[0].id;
        paso('Hay al menos un técnico para asignar', Boolean(tecnicoId));
        if (!tecnicoId) return;

        const form = await api('POST', '/api/formularios', token, { nombre: `Visita ${marca}`, puntos: ['Relevar extintores', 'Sacar fotos'] });
        formularioId = form.datos && form.datos.id;
        paso('Se crea un formulario de visita', form.status === 200 && form.datos.puntos.length === 2);

        const orden = await api('POST', '/api/ordenes', token, {
            tecnico_id: tecnicoId,
            nombre_cliente: cliente,
            direccion_trabajo: 'Calle Falsa 123, Córdoba',
            descripcion_tarea: 'Notas',
            fecha_asignada: '2026-11-03',
            hora_ejecucion: '09:30',
            formulario_id: formularioId,
        });
        ordenId = orden.datos && orden.datos.id;
        paso('La orden queda en el día elegido y copia el formulario', orden.status === 200 && String(orden.datos.fecha_asignada).includes('2026-11-03') && Array.isArray(orden.datos.puntos) && orden.datos.puntos.length === 2, JSON.stringify(orden.datos && orden.datos.fecha_asignada));

        const lista = await api('GET', '/api/ordenes', token);
        const enLista = Array.isArray(lista.datos) && lista.datos.find((o) => o.id === ordenId);
        paso('El calendario recibe la fecha como día, sin correrse', lista.status === 200 && enLista && enLista.fecha_dia === '2026-11-03', enLista && enLista.fecha_dia);

        const aviso = await api('POST', `/api/ordenes/${ordenId}/avisar`, token, {});
        paso('Sin correo del cliente no se manda el aviso', aviso.status === 400);

        const seguimiento = await api('GET', '/seguimiento/no-es-un-token', null);
        paso('Un enlace de seguimiento inventado no abre', seguimiento.status === 404);

        const analisis = await api('GET', '/api/analisis', token);
        paso('El análisis trae tiempos y encuestas', analisis.status === 200 && Array.isArray(analisis.datos.tiempos) && analisis.datos.encuestas);

        const emailTec = `campo.${marca}@son.test`;
        const alta = await api('POST', '/api/tecnicos', token, { nombre: 'Tecnico Campo', email: emailTec, password: 'Prueba123' });
        const tec = await api('POST', '/api/tecnicos/login', null, { email: emailTec, password: 'Prueba123' });
        const pedido = await api('POST', '/api/ordenes/pedir', tec.datos.token, {
            nombre_cliente: cliente, direccion: 'Otra 9', descripcion: 'Volver la semana que viene', fecha: '2026-11-04',
        });
        paso('El técnico puede pedir una visita sin asignar', pedido.status === 200 && pedido.datos.estado === 'Por asignar');
        if (pedido.datos && pedido.datos.id) {
            await pool.query('DELETE FROM ordenes WHERE id = $1', [pedido.datos.id]);
        }
        if (alta.datos && alta.datos.id) await pool.query('DELETE FROM tecnicos WHERE id = $1', [alta.datos.id]);
    } catch (error) {
        paso('La prueba terminó sin un error inesperado', false, error.message);
    } finally {
        if (ordenId) await pool.query('DELETE FROM ordenes WHERE id = $1', [ordenId]);
        if (formularioId) await pool.query('DELETE FROM formularios_visita WHERE id = $1', [formularioId]);
        await pool.query('DELETE FROM empresas WHERE razon_social = $1', [cliente]);
        await pool.end();
        console.log(fallos ? `RESULTADO: ${fallos} fallas` : 'RESULTADO: todo OK');
        process.exit(fallos ? 1 : 0);
    }
})();
