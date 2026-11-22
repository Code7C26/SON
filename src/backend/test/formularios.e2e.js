// Prueba de los formularios de control: subir el Excel (queda igual que el original), guardarlo,
// usarlo en una orden, completarlo como técnico, que salga en el informe y que sus vencimientos pasen
// a Vencimientos. También un formulario armado a mano (lista de preguntas).
// Uso, con el backend prendido: node test/formularios.e2e.js
//   PRUEBA_URL=http://127.0.0.1:3999  para otro puerto
//   FORMULARIOS_DIR=carpeta           donde están los Excel (por defecto, la de la empresa)
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const BASE = process.env.PRUEBA_URL || `http://127.0.0.1:${process.env.PORT || 3000}`;
const CARPETA = process.env.FORMULARIOS_DIR || '//sa-server/HIGIENE Y SEGURIDAD/05. Controles/00. Formularios Sima a revisar';
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

function excel(nombre) {
    return { archivo: nombre, contenido: fs.readFileSync(path.join(CARPETA, nombre)).toString('base64') };
}

(async () => {
    const marca = Date.now();
    const cliente = `Cliente Formularios ${marca}`;
    const creado = { tecnico: null, formularios: [], orden: null };
    try {
        const login = await api('POST', '/api/admin/login', null, { email: process.env.ADMIN_EMAIL, password: process.env.ADMIN_PASSWORD });
        const token = login.datos && login.datos.token;
        paso('Ingresa el administrador', login.status === 200 && token);

        // --- Subir los Excel: quedan igual que el original ---
        const malo = await api('POST', '/api/formularios/importar', token, { archivo: 'x.xls', contenido: Buffer.from('no soy un excel').toString('base64') });
        paso('Un archivo que no es Excel da un error claro', malo.status === 400 && /excel/i.test(malo.datos.error));

        const extintores = await api('POST', '/api/formularios/importar', token, excel('05-00 Control Equipos Extintores.xls'));
        const dExt = extintores.datos && extintores.datos.definicion;
        paso('Extintores queda igual al Excel (celdas, anchos y altos)', extintores.status === 200 && dExt.tipo === 'excel' && dExt.anchos.length === 15 && dExt.celdas.length > 100);
        paso('Las columnas de vencimiento son casilleros de fecha', dExt && dExt.campos.filter((c) => c.tipo === 'fecha' && /venc/i.test(c.encabezado)).length >= 40);
        paso('Ofrece S / I como respuestas rápidas', dExt && dExt.sugerencias.join() === 'S,I');
        paso('"Empresa:" se completa sola', dExt && dExt.celdas.some((c) => c.auto === 'empresa'));

        const tableros = await api('POST', '/api/formularios/importar', token, excel('05-00- Control  tableros electricos.xls'));
        const dTab = tableros.datos && tableros.datos.definicion;
        const marcas = dTab ? dTab.campos.filter((c) => c.tipo === 'marca') : [];
        paso('Tableros: las columnas SI / NO / NC se marcan con X', tableros.status === 200 && dTab.tipo === 'excel' && marcas.length > 100 && dTab.opciones.join() === 'SI,NO,NC');

        // --- Formulario a mano (lista) ---
        const sinPreguntas = await api('POST', '/api/formularios', token, { nombre: 'Vacío', definicion: { tipo: 'lista', opciones: ['SI', 'NO'], preguntas: [] } });
        paso('No deja guardar un formulario a mano sin preguntas', sinPreguntas.status === 400);
        const sinCasilleros = await api('POST', '/api/formularios', token, { nombre: 'Roto', definicion: { ...dTab, campos: [] } });
        paso('No deja guardar una planilla sin casilleros', sinCasilleros.status === 400);

        for (const [definicion, nombre, archivo] of [
            [dExt, `Extintores ${marca}`, extintores.datos.archivo],
            [dTab, `Tableros ${marca}`, tableros.datos.archivo],
            [{ tipo: 'lista', opciones: ['SI', 'NO'], preguntas: ['¿Orden y limpieza?', '¿Salidas despejadas?'] }, `A mano ${marca}`, null],
        ]) {
            const guardado = await api('POST', '/api/formularios', token, { nombre, definicion, archivo });
            if (guardado.datos && guardado.datos.id) creado.formularios.push(guardado.datos.id);
        }
        paso('Se guardan los tres formularios', creado.formularios.length === 3);

        // --- Orden con formularios, guardados como fijos de la empresa ---
        const tec = await api('POST', '/api/tecnicos', token, { nombre: 'Tec Formularios', email: `form.${marca}@son.test`, password: 'Prueba123' });
        creado.tecnico = tec.datos && tec.datos.id;
        const hoy = new Date();
        const dia = `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-${String(hoy.getDate()).padStart(2, '0')}`;
        const t0 = Date.now();
        const orden = await api('POST', '/api/ordenes', token, {
            tecnico_id: creado.tecnico, nombre_cliente: cliente, direccion_trabajo: 'Av. Colón 500, Córdoba', fecha_asignada: dia,
            puntos: ['Recorrida general'], formularios: creado.formularios, guardar_tareas_fijas: true,
        });
        creado.orden = orden.datos && orden.datos.id;
        paso('La orden se guarda rápido (el recorrido se ordena después)', orden.status === 200 && Date.now() - t0 < 1500, `${Date.now() - t0} ms`);
        paso('La orden lleva los formularios', Array.isArray(orden.datos.formularios) && orden.datos.formularios.length === 3);
        const fijos = await api('GET', `/api/clientes/tareas?nombre=${encodeURIComponent(cliente)}`, token);
        paso('Quedan como formularios fijos de la empresa', fijos.status === 200 && fijos.datos.formularios.length === 3);
        const otra = await api('POST', '/api/ordenes', token, { tecnico_id: creado.tecnico, nombre_cliente: cliente, direccion_trabajo: 'Av. Colón 500, Córdoba', fecha_asignada: dia });
        paso('Una orden nueva de esa empresa los trae sola', otra.status === 200 && Array.isArray(otra.datos.formularios) && otra.datos.formularios.length === 3);
        if (otra.datos && otra.datos.id) await pool.query('DELETE FROM ordenes WHERE id = $1', [otra.datos.id]);

        // --- El técnico completa ---
        const loginTec = await api('POST', '/api/tecnicos/login', null, { email: `form.${marca}@son.test`, password: 'Prueba123' });
        const tokenTec = loginTec.datos.token;
        const suyas = await api('GET', `/api/ordenes/tecnico/${creado.tecnico}`, tokenTec);
        const suya = Array.isArray(suyas.datos) && suyas.datos.find((o) => o.id === creado.orden);
        paso('El técnico recibe los formularios en la orden', suya && Array.isArray(suya.formularios) && suya.formularios.length === 3);

        const [idExt, idTab, idMano] = creado.formularios;
        const enUnMes = new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10);
        // Extintores: un renglón con ubicación, N° y vencimiento de carga.
        const filaExt = dExt.campos.find((c) => c.tipo === 'fecha' && /carga/i.test(c.encabezado)).f;
        const enFila = (encabezado) => dExt.campos.find((c) => c.f === filaExt && new RegExp(encabezado, 'i').test(c.encabezado || ''));
        const valoresExt = {
            [`${enFila('^ubicaci').f},${enFila('^ubicaci').c}`]: 'Depósito',
            [`${enFila('^n').f},${enFila('^n').c}`]: '12',
            [`${enFila('carga').f},${enFila('carga').c}`]: enUnMes,
            [`${enFila('PH').f},${enFila('PH').c}`]: 'no-es-fecha',
        };
        // Tableros: SI y NO en la misma pregunta (solo debe quedar una) y un casillero que no existe.
        const primeraFila = marcas[0].f;
        const deUnaPregunta = marcas.filter((c) => c.f === primeraFila && c.grupo === marcas[0].grupo);
        const valoresTab = { [`${deUnaPregunta[0].f},${deUnaPregunta[0].c}`]: 'X', [`${deUnaPregunta[1].f},${deUnaPregunta[1].c}`]: 'X', '999,999': 'X' };
        const informe = await api('POST', '/api/generar-informe', tokenTec, {
            ordenId: creado.orden, cliente, direccion: 'Av. Colón 500, Córdoba', comentarios: 'Visita con formularios',
            checklist: [{ tarea: 'Recorrida general', hecho: true }],
            formularios: [
                { id: idExt, valores: valoresExt, observacion: 'Precinto roto en el N° 12' },
                { id: idTab, valores: valoresTab },
                { id: idMano, respuestas: [{ valores: ['SI'] }, { valores: ['TAL VEZ'] }] },
                { id: 999999, valores: {} },
            ],
            inicio: new Date(Date.now() - 3600000).toISOString(), fin: new Date().toISOString(), sinPdf: true,
        });
        paso('Se genera el informe con los formularios', informe.status === 200 && informe.datos.ok);

        const cierre = await pool.query('SELECT formularios_cierre FROM ordenes WHERE id = $1', [creado.orden]);
        const guardados = cierre.rows[0] && cierre.rows[0].formularios_cierre;
        const fExt = guardados && guardados.find((f) => f.id === idExt);
        const fTab = guardados && guardados.find((f) => f.id === idTab);
        const fMano = guardados && guardados.find((f) => f.id === idMano);
        paso('Se guardan solo los formularios de la orden', Array.isArray(guardados) && guardados.length === 3);
        paso('En extintores se guardan los casilleros y se descarta la fecha inválida', fExt && fExt.contestadas === 3 && fExt.filasCompletadas === 1);
        paso('En tableros queda una sola marca por pregunta y nada fuera de la planilla', fTab && fTab.contestadas === 1 && !fTab.valores['999,999']);
        paso('El formulario a mano guarda sus respuestas', fMano && fMano.respuestas[0].valores[0] === 'SI' && fMano.respuestas[1].valores[0] === null);
        const vencimientos = await pool.query('SELECT descripcion, to_char(vence, \'YYYY-MM-DD\') AS vence FROM vencimientos WHERE orden_id = $1 ORDER BY vence', [creado.orden]);
        paso('El vencimiento del extintor pasa a Vencimientos', vencimientos.rows.length === 1 && vencimientos.rows[0].vence === enUnMes && /Depósito/.test(vencimientos.rows[0].descripcion), JSON.stringify(vencimientos.rows));
    } catch (error) {
        paso('La prueba terminó sin un error inesperado', false, error.stack);
    } finally {
        if (creado.orden) {
            await pool.query('DELETE FROM vencimientos WHERE orden_id = $1', [creado.orden]).catch(() => {});
            await pool.query('DELETE FROM visitas WHERE orden_id = $1', [creado.orden]).catch(() => {});
            await pool.query('DELETE FROM encuestas WHERE orden_id = $1', [creado.orden]).catch(() => {});
            await pool.query('DELETE FROM ordenes WHERE id = $1', [creado.orden]).catch(() => {});
        }
        await pool.query('DELETE FROM empresas WHERE razon_social = $1', [cliente]).catch(() => {});
        if (creado.formularios.length) await pool.query('DELETE FROM formularios_visita WHERE id = ANY($1)', [creado.formularios]).catch(() => {});
        if (creado.tecnico) await pool.query('DELETE FROM tecnicos WHERE id = $1', [creado.tecnico]).catch(() => {});
        await pool.end();
        console.log(fallos ? `RESULTADO: ${fallos} fallas` : 'RESULTADO: todo OK');
        process.exit(fallos ? 1 : 0);
    }
})();
