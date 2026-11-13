// CRM comercial (lo que hacía la planilla "CRM Comercial SIMA", ahora dentro de Presupuestos):
//  - Bitácora de contactos con cada cliente (llamada, visita, mail...) y pendientes con fecha y responsable.
//  - Alerta de días sin contacto según el tipo de cliente (un prospecto se llama más seguido que un mensualizado).
//  - Conversión: cuántos presupuestos enviados se ganaron, por servicio, por responsable y por qué se perdieron.
// Todo es del área comercial (solo Comercial).

const CONFIG_POR_DEFECTO = {
    umbrales: { Prospecto: 7, Mensualizado: 30, Eventual: 60, 'Ex Cliente': 180, Otro: 60 },
    umbralPresupuesto: 14,
    tiposNota: ['Visita', 'Llamada', 'Mail', 'WhatsApp', 'Reunión', 'Interna'],
    servicios: [
        'Servicio mensual HyS', 'Servicio mensual Medio Ambiente', 'Estación de servicio (EESS)', 'Habilitación o trámite',
        'Estudio o informe ambiental', 'Mediciones (ruido, iluminación, PAT)', 'Capacitación', 'Otro',
    ],
    responsables: [],
    razonesPerdida: ['Precio', 'Funcionalidad', 'Competidor', 'Otro'],
};
const CLAVE_CONFIG = 'crm';
// Las notas "Interna" no cuentan como contacto con el cliente.
const NO_CUENTA_COMO_CONTACTO = ['Interna'];

function vacio(valor) {
    return valor === undefined || valor === null || valor === '';
}

function entero(valor) {
    if (typeof valor === 'number') return Number.isInteger(valor) ? valor : NaN;
    if (typeof valor === 'string' && /^\d{1,9}$/.test(valor.trim())) return Number(valor.trim());
    return NaN;
}

function texto(valor, maximo) {
    const limpio = String(valor ?? '').trim();
    return limpio ? limpio.slice(0, maximo) : null;
}

function fechaValida(valor) {
    const limpio = String(valor || '').slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(limpio)) return null;
    const [anio, mes, dia] = limpio.split('-').map(Number);
    const fecha = new Date(Date.UTC(anio, mes - 1, dia));
    return fecha.getUTCFullYear() === anio && fecha.getUTCMonth() === mes - 1 && fecha.getUTCDate() === dia ? limpio : null;
}

function listaDeTextos(valor, maximo = 60) {
    if (!Array.isArray(valor)) return null;
    const vistos = new Set();
    const lista = [];
    for (const item of valor) {
        const limpio = texto(item, 80);
        if (limpio && !vistos.has(limpio.toLowerCase())) {
            vistos.add(limpio.toLowerCase());
            lista.push(limpio);
        }
    }
    return lista.slice(0, maximo);
}

async function leerConfig(pool) {
    const fila = await pool.query('SELECT valor FROM configuracion_comercial WHERE clave = $1', [CLAVE_CONFIG]);
    const guardada = fila.rows[0] ? fila.rows[0].valor : {};
    return { ...CONFIG_POR_DEFECTO, ...(guardada && typeof guardada === 'object' ? guardada : {}) };
}

// Semáforo de contacto: verde al día, amarillo cerca del umbral, rojo pasado, "sin" si nunca se lo contactó.
function alertaDeContacto(ultimoContacto, umbral, hoy = new Date()) {
    if (!ultimoContacto) return { estado: 'sin', dias: null, umbral };
    const ultimo = new Date(`${String(ultimoContacto).slice(0, 10)}T00:00:00Z`);
    const base = Date.UTC(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
    const dias = Math.max(0, Math.round((base - ultimo.getTime()) / 86400000));
    const estado = dias > umbral ? 'rojo' : dias >= umbral * 0.75 ? 'amarillo' : 'verde';
    return { estado, dias, umbral };
}

// Presupuesto "vigente" = la última versión de cada número.
const ULTIMA_VERSION = 'NOT EXISTS (SELECT 1 FROM presupuestos p2 WHERE p2.numero = p.numero AND p2.version > p.version)';
const ESTADOS_ABIERTOS = ['Borrador', 'Enviado', 'Negociando'];

const SELECT_NOTA = `
    SELECT n.id, n.empresa_id, e.razon_social AS empresa, to_char(n.fecha, 'YYYY-MM-DD') AS fecha, n.tipo, n.texto,
           n.pendiente, to_char(n.pendiente_fecha, 'YYYY-MM-DD') AS pendiente_fecha, n.pendiente_responsable,
           n.pendiente_hecho, n.autor, n.creada_en
    FROM crm_notas n
    JOIN empresas e ON e.id = n.empresa_id
`;

function datosDeNota(cuerpo, config) {
    const fecha = vacio(cuerpo.fecha) ? null : fechaValida(cuerpo.fecha);
    if (!vacio(cuerpo.fecha) && !fecha) return { error: 'La fecha no es válida' };
    const tipo = texto(cuerpo.tipo, 40) || 'Llamada';
    const notaTexto = texto(cuerpo.texto, 8000);
    const pendiente = texto(cuerpo.pendiente, 300);
    const pendienteFecha = vacio(cuerpo.pendienteFecha) ? null : fechaValida(cuerpo.pendienteFecha);
    if (!vacio(cuerpo.pendienteFecha) && !pendienteFecha) return { error: 'La fecha del pendiente no es válida' };
    if (!notaTexto && !pendiente) return { error: 'Escribí la nota o el pendiente' };
    if (!config.tiposNota.includes(tipo) && tipo.length > 40) return { error: 'Tipo de nota inválido' };
    return {
        datos: {
            fecha, tipo, texto: notaTexto, pendiente,
            pendiente_fecha: pendiente ? pendienteFecha : null,
            pendiente_responsable: pendiente ? texto(cuerpo.pendienteResponsable, 80) : null,
        },
    };
}

function celdaCsv(valor) {
    const limpio = valor === null || valor === undefined ? '' : String(valor);
    return /[";\n]/.test(limpio) ? `"${limpio.replace(/"/g, '""')}"` : limpio;
}

function fechaArgentina(iso) {
    const partes = String(iso || '').slice(0, 10).split('-');
    return partes.length === 3 ? `${partes[2]}/${partes[1]}/${partes[0]}` : '';
}

function registrarRutasCrm(app, { pool, soloComercial }) {
    async function nombreDe(req) {
        const fila = await pool.query('SELECT nombre FROM admins WHERE id = $1', [req.usuario.id]);
        return fila.rows[0] ? fila.rows[0].nombre : null;
    }

    app.get('/api/crm/config', soloComercial, async (req, res) => {
        try {
            const config = await leerConfig(pool);
            // Si no se cargaron responsables, se sugieren los usuarios del panel.
            if (!config.responsables.length) {
                const cuentas = await pool.query("SELECT nombre FROM admins WHERE rol = 'comercial' ORDER BY nombre");
                config.responsables = cuentas.rows.map((fila) => fila.nombre);
            }
            res.json(config);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer la configuración del CRM' });
        }
    });

    app.put('/api/crm/config', soloComercial, async (req, res) => {
        const cuerpo = req.body || {};
        try {
            const actual = await leerConfig(pool);
            const nueva = { ...actual };
            if (cuerpo.umbrales !== undefined) {
                if (!cuerpo.umbrales || typeof cuerpo.umbrales !== 'object') return res.status(400).json({ error: 'Umbrales inválidos' });
                const umbrales = {};
                for (const [tipo, dias] of Object.entries(cuerpo.umbrales)) {
                    const nombre = texto(tipo, 40);
                    const numero = Number(dias);
                    if (!nombre || !Number.isInteger(numero) || numero < 1 || numero > 3650) return res.status(400).json({ error: `El umbral de "${tipo}" tiene que ser un número de días entre 1 y 3650` });
                    umbrales[nombre] = numero;
                }
                if (!Object.keys(umbrales).length) return res.status(400).json({ error: 'Tiene que quedar al menos un tipo de cliente' });
                nueva.umbrales = umbrales;
            }
            if (cuerpo.umbralPresupuesto !== undefined) {
                const numero = Number(cuerpo.umbralPresupuesto);
                if (!Number.isInteger(numero) || numero < 1 || numero > 365) return res.status(400).json({ error: 'El umbral con presupuesto abierto tiene que estar entre 1 y 365 días' });
                nueva.umbralPresupuesto = numero;
            }
            for (const clave of ['tiposNota', 'servicios', 'responsables', 'razonesPerdida']) {
                if (cuerpo[clave] === undefined) continue;
                const lista = listaDeTextos(cuerpo[clave]);
                if (!lista) return res.status(400).json({ error: `La lista "${clave}" no es válida` });
                nueva[clave] = lista;
            }
            await pool.query(
                `INSERT INTO configuracion_comercial (clave, valor, actualizada_en) VALUES ($1, $2::jsonb, now())
                 ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor, actualizada_en = now()`,
                [CLAVE_CONFIG, JSON.stringify(nueva)]
            );
            res.json(nueva);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar la configuración del CRM' });
        }
    });

    // Todos los clientes con su semáforo de contacto, pendientes y presupuestos abiertos.
    app.get('/api/crm/clientes', soloComercial, async (req, res) => {
        try {
            const config = await leerConfig(pool);
            const filas = await pool.query(
                `SELECT e.id, e.razon_social, e.tipo_cliente, e.categoria, e.actividad, e.contacto, e.telefono, e.email,
                        (SELECT to_char(MAX(n.fecha), 'YYYY-MM-DD') FROM crm_notas n
                          WHERE n.empresa_id = e.id AND n.tipo <> ALL($1)) AS ultimo_contacto,
                        (SELECT COUNT(*)::int FROM crm_notas n
                          WHERE n.empresa_id = e.id AND n.pendiente IS NOT NULL AND n.pendiente_hecho = false) AS pendientes,
                        (SELECT COUNT(*)::int FROM presupuestos p
                          WHERE p.empresa_id = e.id AND p.estado = ANY($2) AND ${ULTIMA_VERSION}) AS presupuestos_abiertos
                 FROM empresas e
                 ORDER BY lower(e.razon_social)`,
                [NO_CUENTA_COMO_CONTACTO, ESTADOS_ABIERTOS]
            );
            const hoy = new Date();
            res.json(filas.rows.map((fila) => {
                let umbral = Number(config.umbrales[fila.tipo_cliente || 'Otro'] ?? config.umbrales.Otro ?? 60);
                if (fila.presupuestos_abiertos > 0) umbral = Math.min(umbral, Number(config.umbralPresupuesto || 14));
                return { ...fila, alerta: alertaDeContacto(fila.ultimo_contacto, umbral, hoy) };
            }));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudieron leer los clientes del CRM' });
        }
    });

    app.put('/api/crm/clientes/:id', soloComercial, async (req, res) => {
        const id = entero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Cliente inválido' });
        const tipo = texto(req.body && req.body.tipo_cliente, 40);
        try {
            const cambio = await pool.query('UPDATE empresas SET tipo_cliente = $1 WHERE id = $2', [tipo, id]);
            if (!cambio.rowCount) return res.status(404).json({ error: 'Ese cliente no existe' });
            res.json({ ok: true, tipo_cliente: tipo });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar el tipo de cliente' });
        }
    });

    // Bitácora de un cliente, o de todos si no se indica.
    app.get('/api/crm/notas', soloComercial, async (req, res) => {
        const valores = [];
        let donde = '';
        if (!vacio(req.query.empresaId)) {
            const id = entero(req.query.empresaId);
            if (Number.isNaN(id)) return res.status(400).json({ error: 'Cliente inválido' });
            valores.push(id);
            donde = 'WHERE n.empresa_id = $1';
        }
        try {
            const filas = await pool.query(`${SELECT_NOTA} ${donde} ORDER BY n.fecha DESC, n.id DESC LIMIT 2000`, valores);
            res.json(filas.rows);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer la bitácora' });
        }
    });

    app.post('/api/crm/notas', soloComercial, async (req, res) => {
        const cuerpo = req.body || {};
        const empresaId = entero(cuerpo.empresaId);
        if (Number.isNaN(empresaId)) return res.status(400).json({ error: 'Elegí el cliente' });
        try {
            const config = await leerConfig(pool);
            const nota = datosDeNota(cuerpo, config);
            if (nota.error) return res.status(400).json({ error: nota.error });
            const existe = await pool.query('SELECT 1 FROM empresas WHERE id = $1', [empresaId]);
            if (!existe.rows.length) return res.status(404).json({ error: 'Ese cliente no existe' });
            const d = nota.datos;
            const nueva = await pool.query(
                `INSERT INTO crm_notas (empresa_id, fecha, tipo, texto, pendiente, pendiente_fecha, pendiente_responsable, autor)
                 VALUES ($1, COALESCE($2::date, CURRENT_DATE), $3, $4, $5, $6, $7, $8) RETURNING id`,
                [empresaId, d.fecha, d.tipo, d.texto, d.pendiente, d.pendiente_fecha, d.pendiente_responsable, await nombreDe(req)]
            );
            const fila = await pool.query(`${SELECT_NOTA} WHERE n.id = $1`, [nueva.rows[0].id]);
            res.json(fila.rows[0]);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar la nota' });
        }
    });

    app.put('/api/crm/notas/:id', soloComercial, async (req, res) => {
        const id = entero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Nota inválida' });
        const cuerpo = req.body || {};
        try {
            // Tildar o destildar un pendiente no toca el resto de la nota.
            if (Object.keys(cuerpo).length === 1 && typeof cuerpo.pendienteHecho === 'boolean') {
                const cambio = await pool.query('UPDATE crm_notas SET pendiente_hecho = $1 WHERE id = $2', [cuerpo.pendienteHecho, id]);
                if (!cambio.rowCount) return res.status(404).json({ error: 'Esa nota no existe' });
            } else {
                const config = await leerConfig(pool);
                const nota = datosDeNota(cuerpo, config);
                if (nota.error) return res.status(400).json({ error: nota.error });
                const d = nota.datos;
                const cambio = await pool.query(
                    `UPDATE crm_notas SET fecha = COALESCE($1::date, fecha), tipo = $2, texto = $3, pendiente = $4, pendiente_fecha = $5,
                            pendiente_responsable = $6, pendiente_hecho = COALESCE($7, pendiente_hecho)
                     WHERE id = $8`,
                    [d.fecha, d.tipo, d.texto, d.pendiente, d.pendiente_fecha, d.pendiente_responsable,
                        typeof cuerpo.pendienteHecho === 'boolean' ? cuerpo.pendienteHecho : null, id]
                );
                if (!cambio.rowCount) return res.status(404).json({ error: 'Esa nota no existe' });
            }
            const fila = await pool.query(`${SELECT_NOTA} WHERE n.id = $1`, [id]);
            res.json(fila.rows[0]);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar la nota' });
        }
    });

    app.delete('/api/crm/notas/:id', soloComercial, async (req, res) => {
        const id = entero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Nota inválida' });
        try {
            const borrado = await pool.query('DELETE FROM crm_notas WHERE id = $1', [id]);
            if (!borrado.rowCount) return res.status(404).json({ error: 'Esa nota no existe' });
            res.json({ ok: true });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo borrar la nota' });
        }
    });

    // Compromisos pendientes de todos los clientes, del más atrasado al más lejano.
    app.get('/api/crm/pendientes', soloComercial, async (req, res) => {
        const conHechos = req.query.hechos === '1';
        try {
            const filas = await pool.query(
                `${SELECT_NOTA} WHERE n.pendiente IS NOT NULL ${conHechos ? '' : 'AND n.pendiente_hecho = false'}
                 ORDER BY n.pendiente_hecho, n.pendiente_fecha ASC NULLS LAST, n.id LIMIT 1000`
            );
            res.json(filas.rows);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudieron leer los pendientes' });
        }
    });

    // Conversión: de los presupuestos enviados en el período, cuántos se ganaron.
    app.get('/api/crm/conversion', soloComercial, async (req, res) => {
        const desde = fechaValida(req.query.desde) || '1900-01-01';
        const hasta = fechaValida(req.query.hasta) || '2999-12-31';
        try {
            const filas = await pool.query(
                `SELECT p.id, p.numero, p.estado, p.responsable, p.servicio, p.razon_perdida, to_char(p.fecha_envio, 'YYYY-MM-DD') AS fecha_envio
                 FROM presupuestos p
                 WHERE ${ULTIMA_VERSION} AND p.fecha_envio IS NOT NULL AND p.fecha_envio BETWEEN $1::date AND $2::date`,
                [desde, hasta]
            );
            const lista = filas.rows;
            const contar = (estado) => lista.filter((p) => p.estado === estado).length;
            const agrupar = (clave) => {
                const grupos = new Map();
                for (const p of lista) {
                    const nombre = p[clave] || 'Sin dato';
                    const grupo = grupos.get(nombre) || { nombre, enviados: 0, ganados: 0 };
                    grupo.enviados += 1;
                    if (p.estado === 'Aceptado') grupo.ganados += 1;
                    grupos.set(nombre, grupo);
                }
                return [...grupos.values()].sort((a, b) => b.enviados - a.enviados);
            };
            const razones = new Map();
            for (const p of lista.filter((item) => item.estado === 'Rechazado')) {
                const razon = p.razon_perdida || 'Sin razón';
                razones.set(razon, (razones.get(razon) || 0) + 1);
            }
            const ganados = contar('Aceptado');
            res.json({
                desde, hasta,
                enviados: lista.length,
                ganados,
                perdidos: contar('Rechazado'),
                negociando: contar('Enviado') + contar('Negociando'),
                porcentaje: lista.length ? Math.round((ganados / lista.length) * 100) : null,
                porServicio: agrupar('servicio'),
                porResponsable: agrupar('responsable'),
                razonesPerdida: [...razones.entries()].map(([razon, cantidad]) => ({ razon, cantidad })).sort((a, b) => b.cantidad - a.cantidad),
            });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo calcular la conversión' });
        }
    });

    // Planilla para Excel: clientes, presupuestos o bitácora.
    app.get('/api/crm/planilla', soloComercial, async (req, res) => {
        const tipo = ['clientes', 'presupuestos', 'bitacora'].includes(req.query.tipo) ? req.query.tipo : 'presupuestos';
        try {
            let encabezado;
            let filas;
            if (tipo === 'bitacora') {
                const datos = await pool.query(`${SELECT_NOTA} ORDER BY n.fecha DESC, n.id DESC`);
                encabezado = ['Fecha', 'Cliente', 'Tipo', 'Nota', 'Autor', 'Pendiente', 'Fecha compromiso', 'Responsable', 'Hecho'];
                filas = datos.rows.map((n) => [fechaArgentina(n.fecha), n.empresa, n.tipo, n.texto, n.autor, n.pendiente,
                    fechaArgentina(n.pendiente_fecha), n.pendiente_responsable, n.pendiente ? (n.pendiente_hecho ? 'Sí' : 'No') : '']);
            } else if (tipo === 'clientes') {
                const config = await leerConfig(pool);
                const datos = await pool.query(
                    `SELECT e.razon_social, e.tipo_cliente, e.categoria, e.actividad, e.contacto, e.telefono, e.email,
                            (SELECT to_char(MAX(n.fecha), 'YYYY-MM-DD') FROM crm_notas n WHERE n.empresa_id = e.id AND n.tipo <> ALL($1)) AS ultimo
                     FROM empresas e ORDER BY lower(e.razon_social)`,
                    [NO_CUENTA_COMO_CONTACTO]
                );
                encabezado = ['Cliente', 'Tipo', 'Categoría', 'Actividad', 'Contacto', 'Teléfono', 'Correo', 'Último contacto', 'Días sin contacto'];
                filas = datos.rows.map((e) => {
                    const alerta = alertaDeContacto(e.ultimo, Number(config.umbrales[e.tipo_cliente || 'Otro'] ?? 60));
                    return [e.razon_social, e.tipo_cliente, e.categoria, e.actividad, e.contacto, e.telefono, e.email, fechaArgentina(e.ultimo), alerta.dias ?? ''];
                });
            } else {
                const datos = await pool.query(
                    `SELECT p.numero, p.version, p.cliente->>'razonSocial' AS cliente_texto, e.razon_social, p.estado, p.servicio, p.prioridad,
                            p.responsable, to_char(p.fecha, 'YYYY-MM-DD') AS fecha, to_char(p.fecha_envio, 'YYYY-MM-DD') AS envio,
                            to_char(p.fecha_limite, 'YYYY-MM-DD') AS limite, p.razon_perdida, p.facturado
                     FROM presupuestos p LEFT JOIN empresas e ON e.id = p.empresa_id
                     WHERE ${ULTIMA_VERSION} ORDER BY p.numero DESC`
                );
                encabezado = ['Número', 'Cliente', 'Estado', 'Servicio', 'Prioridad', 'Responsable', 'Fecha', 'Enviado', 'Fecha límite', 'Razón de pérdida', 'Facturado'];
                filas = datos.rows.map((p) => [`${p.numero}${p.version > 1 ? ` act ${p.version - 1}` : ''}`, p.razon_social || p.cliente_texto, p.estado,
                    p.servicio, p.prioridad, p.responsable, fechaArgentina(p.fecha), fechaArgentina(p.envio), fechaArgentina(p.limite),
                    p.razon_perdida, p.facturado ? 'Sí' : 'No']);
            }
            const ahora = new Date();
            const marca = `${ahora.getFullYear()}-${String(ahora.getMonth() + 1).padStart(2, '0')}-${String(ahora.getDate()).padStart(2, '0')}`;
            res.setHeader('Content-Type', 'text/csv; charset=utf-8');
            res.setHeader('Content-Disposition', `attachment; filename="crm_${tipo}_${marca}.csv"`);
            res.send('﻿' + [encabezado, ...filas].map((fila) => fila.map(celdaCsv).join(';')).join('\r\n'));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo armar la planilla' });
        }
    });
}

module.exports = { registrarRutasCrm, alertaDeContacto, CONFIG_POR_DEFECTO };
