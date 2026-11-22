// Lo que pidieron los técnicos en la reunión de noviembre de 2026:
//  - Gastos y kilometraje del vehículo (reemplaza el Forms de gastos): el técnico los carga desde la orden.
//  - Vencimientos (extintores, mediciones, habilitaciones): avisan con tiempo al técnico y a la oficina.
//  - El técnico ve en qué quedó cada cosa que pidió presupuestar (pedido, presupuestado, enviado, aprobado).
//  - Acceso del cliente: un enlace privado donde ve sus informes, próximas visitas y vencimientos.
const { enviarCorreo } = require('./correo');
const { pagina, escapar, tokenNuevo, tokenValido, rutaDelInforme, raizPublica } = require('./campo');

const TIPOS_GASTO = ['Combustible', 'Peaje', 'Estacionamiento', 'Comida', 'Hospedaje', 'Materiales', 'Otro'];
const MAX_FOTO_BYTES = 4 * 1024 * 1024;
const DIAS_AVISO_VENCIMIENTO = Number(process.env.DIAS_AVISO_VENCIMIENTO) || 60;

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

function idDeLaApp(valor) {
    const limpio = String(valor || '');
    return /^[A-Za-z0-9_-]{8,64}$/.test(limpio) ? limpio : null;
}

// La hora en que el técnico cargó algo (puede ser de días atrás si estaba sin señal).
function momentoDeLaApp(valor) {
    if (vacio(valor)) return null;
    const fecha = new Date(valor);
    if (Number.isNaN(fecha.getTime())) return null;
    const ahora = Date.now();
    if (fecha.getTime() > ahora + 5 * 60 * 1000 || fecha.getTime() < ahora - 60 * 24 * 60 * 60 * 1000) return null;
    return fecha;
}

function tipoDeImagen(bytes) {
    if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
    if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
    if (bytes.length >= 12 && bytes.subarray(0, 4).toString('latin1') === 'RIFF' && bytes.subarray(8, 12).toString('latin1') === 'WEBP') return 'image/webp';
    return null;
}

function leerFoto(valor) {
    if (vacio(valor)) return { foto: null, tipo: null };
    const crudo = String(valor);
    const coma = crudo.indexOf(',');
    if (coma < 0 || !/^data:image\/(jpeg|png|webp);base64$/.test(crudo.slice(0, coma))) return { error: 'La foto no es una imagen válida' };
    const bytes = Buffer.from(crudo.slice(coma + 1), 'base64');
    if (!bytes.length) return { error: 'La foto está vacía' };
    if (bytes.length > MAX_FOTO_BYTES) return { error: 'La foto es demasiado grande (máximo 4 MB)' };
    const tipo = tipoDeImagen(bytes);
    if (!tipo) return { error: 'La foto no es una imagen válida' };
    return { foto: bytes, tipo };
}

function hoyISO() {
    const ahora = new Date();
    return `${ahora.getFullYear()}-${String(ahora.getMonth() + 1).padStart(2, '0')}-${String(ahora.getDate()).padStart(2, '0')}`;
}

function fechaArgentina(iso) {
    const partes = String(iso || '').slice(0, 10).split('-');
    return partes.length === 3 ? `${partes[2]}/${partes[1]}/${partes[0]}` : '';
}

async function empresaDeOrden(pool, ordenId) {
    if (Number.isNaN(entero(ordenId))) return null;
    const fila = await pool.query(
        `SELECT o.id, o.empresa_id, e.razon_social FROM ordenes o LEFT JOIN empresas e ON e.id = o.empresa_id WHERE o.id = $1`,
        [entero(ordenId)]
    );
    return fila.rows[0] || null;
}

async function empresaPorNombre(pool, nombre) {
    const limpio = texto(nombre, 150);
    if (!limpio) return null;
    const fila = await pool.query(
        'SELECT id, razon_social FROM empresas WHERE lower(btrim(razon_social)) = lower(btrim($1)) ORDER BY id LIMIT 1',
        [limpio]
    );
    return fila.rows[0] || null;
}

// --- Estado de lo que pidió presupuestar el técnico, en palabras de la calle ---
// Si la nota quedó dentro de un presupuesto, manda el estado de la última versión de ese presupuesto.
function estadoParaTecnico(estadoNota, estadoPresupuesto) {
    if (estadoNota === 'Descartada') return 'Descartado';
    switch (estadoPresupuesto) {
        case 'Aceptado': return 'Aprobado';
        case 'Rechazado': return 'Rechazado';
        case 'Enviado':
        case 'Negociando': return 'Enviado';
        case 'Borrador': return 'Presupuestando';
        default: break;
    }
    switch (estadoNota) {
        case 'Aprobada': return 'Aprobado';
        case 'Enviada': return 'Enviado';
        case 'Presupuestada': return 'Presupuestado';
        case 'En presupuesto': return 'Presupuestando';
        default: return 'Pedido';
    }
}

// --- Aviso de vencimientos (correo a la oficina y al técnico de ese cliente) ---
async function destinatariosOficina(pool) {
    const fijos = String(process.env.AVISOS_EMAIL || '').split(/[,;\s]+/).map((correo) => correo.trim()).filter(Boolean);
    if (fijos.length) return fijos;
    const cuentas = await pool.query('SELECT email FROM admins ORDER BY id');
    return cuentas.rows.map((fila) => fila.email).filter(Boolean);
}

async function avisarVencimientos(pool) {
    const proximos = await pool.query(
        `SELECT v.id, v.descripcion, v.cantidad, to_char(v.vence, 'YYYY-MM-DD') AS vence,
                COALESCE(e.razon_social, v.empresa_nombre, 'Sin empresa') AS empresa,
                COALESCE(t.email, tu.email) AS email_tecnico
         FROM vencimientos v
         LEFT JOIN empresas e ON e.id = v.empresa_id
         LEFT JOIN tecnicos t ON t.id = v.tecnico_id
         LEFT JOIN LATERAL (
             SELECT tt.email FROM ordenes o JOIN tecnicos tt ON tt.id = o.tecnico_id
             WHERE o.empresa_id = v.empresa_id ORDER BY o.fecha_asignada DESC NULLS LAST LIMIT 1
         ) tu ON true
         WHERE v.resuelto = false AND v.avisado_en IS NULL AND v.vence <= CURRENT_DATE + $1::int
         ORDER BY v.vence`,
        [DIAS_AVISO_VENCIMIENTO]
    );
    if (!proximos.rows.length) return 0;
    const oficina = await destinatariosOficina(pool);
    const porCorreo = new Map();
    const sumar = (correo, fila) => {
        if (!correo) return;
        const clave = correo.toLowerCase();
        if (!porCorreo.has(clave)) porCorreo.set(clave, []);
        porCorreo.get(clave).push(fila);
    };
    for (const fila of proximos.rows) {
        for (const correo of oficina) sumar(correo, fila);
        sumar(fila.email_tecnico, fila);
    }
    let enviados = 0;
    for (const [correo, filas] of porCorreo) {
        const lineas = filas.map((fila) => `• ${fila.empresa}: ${fila.descripcion}${fila.cantidad > 1 ? ` (x${fila.cantidad})` : ''} — vence el ${fechaArgentina(fila.vence)}`);
        try {
            const resultado = await enviarCorreo({
                para: correo,
                asunto: `Vencimientos próximos (${filas.length})`,
                texto: `Estos vencimientos se acercan. Conviene ofrecerle al cliente el cambio en la próxima visita:\n\n${lineas.join('\n')}\n`,
                html: `<p>Estos vencimientos se acercan. Conviene ofrecerle al cliente el cambio en la próxima visita:</p><ul>${filas.map((fila) => `<li><b>${escapar(fila.empresa)}</b>: ${escapar(fila.descripcion)}${fila.cantidad > 1 ? ` (x${fila.cantidad})` : ''} — vence el ${fechaArgentina(fila.vence)}</li>`).join('')}</ul>`,
            });
            if (resultado.enviado) enviados += 1;
            else console.log('Aviso de vencimientos no enviado:', resultado.motivo);
        } catch (error) {
            console.log('Aviso de vencimientos no enviado:', error.message);
        }
    }
    // Se marca como avisado aunque el correo no haya salido: igual se ve en el panel y en la app.
    await pool.query('UPDATE vencimientos SET avisado_en = now() WHERE id = ANY($1)', [proximos.rows.map((fila) => fila.id)]);
    return enviados;
}

const SELECT_VENCIMIENTO = `
    SELECT v.id, v.descripcion, v.cantidad, to_char(v.vence, 'YYYY-MM-DD') AS vence, v.resuelto, v.empresa_id,
           (v.vence - CURRENT_DATE)::int AS dias,
           COALESCE(e.razon_social, v.empresa_nombre, 'Sin empresa') AS empresa,
           v.orden_id, v.creado_por, v.avisado_en, v.creado_en
    FROM vencimientos v
    LEFT JOIN empresas e ON e.id = v.empresa_id
`;

const SELECT_GASTO = `
    SELECT g.id, g.orden_id, g.tecnico_id, COALESCE(t.nombre, g.tecnico_nombre) AS tecnico,
           COALESCE(e.razon_social, g.empresa_nombre) AS empresa,
           g.vehiculo, g.km_inicio, g.km_fin, g.tipo, g.monto::float AS monto, g.descripcion,
           (g.foto IS NOT NULL) AS tiene_foto, g.revisado, g.creado_en,
           to_char(g.creado_en AT TIME ZONE 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD') AS dia
    FROM gastos g
    LEFT JOIN tecnicos t ON t.id = g.tecnico_id
    LEFT JOIN ordenes o ON o.id = g.orden_id
    LEFT JOIN empresas e ON e.id = o.empresa_id
`;

function filtrosDeGastos(consulta) {
    const condiciones = [];
    const valores = [];
    const desde = fechaValida(consulta.desde);
    const hasta = fechaValida(consulta.hasta);
    if (desde) { valores.push(desde); condiciones.push(`(g.creado_en AT TIME ZONE 'America/Argentina/Buenos_Aires')::date >= $${valores.length}::date`); }
    if (hasta) { valores.push(hasta); condiciones.push(`(g.creado_en AT TIME ZONE 'America/Argentina/Buenos_Aires')::date <= $${valores.length}::date`); }
    if (!vacio(consulta.tecnicoId) && !Number.isNaN(entero(consulta.tecnicoId))) { valores.push(entero(consulta.tecnicoId)); condiciones.push(`g.tecnico_id = $${valores.length}`); }
    if (consulta.revisado === 'si') condiciones.push('g.revisado = true');
    if (consulta.revisado === 'no') condiciones.push('g.revisado = false');
    return { donde: condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '', valores };
}

function celdaCsv(valor) {
    const limpio = valor === null || valor === undefined ? '' : String(valor);
    return /[";\n]/.test(limpio) ? `"${limpio.replace(/"/g, '""')}"` : limpio;
}

function registrarRutasOperacion(app, { pool, usuarioDelPanel, soloTecnico, soloComercial }) {
    // ================= GASTOS =================
    app.post('/api/gastos', soloTecnico, async (req, res) => {
        const cuerpo = req.body || {};
        const identificador = idDeLaApp(cuerpo.idCliente);
        if (!identificador) return res.status(400).json({ error: 'Falta el identificador del gasto' });
        const tipo = TIPOS_GASTO.includes(cuerpo.tipo) ? cuerpo.tipo : 'Otro';
        const monto = vacio(cuerpo.monto) ? null : Number(String(cuerpo.monto).replace(',', '.'));
        if (monto !== null && (!Number.isFinite(monto) || monto < 0 || monto > 100000000)) return res.status(400).json({ error: 'El monto no es válido' });
        const kmInicio = vacio(cuerpo.kmInicio) ? null : entero(cuerpo.kmInicio);
        const kmFin = vacio(cuerpo.kmFin) ? null : entero(cuerpo.kmFin);
        if (Number.isNaN(kmInicio) || Number.isNaN(kmFin)) return res.status(400).json({ error: 'El kilometraje tiene que ser un número entero' });
        if (kmInicio !== null && kmFin !== null && kmFin < kmInicio) return res.status(400).json({ error: 'El kilometraje final es menor que el inicial' });
        if (monto === null && kmInicio === null && kmFin === null && vacio(cuerpo.foto) && vacio(cuerpo.descripcion)) {
            return res.status(400).json({ error: 'Cargá el monto, el kilometraje o una foto' });
        }
        const imagen = leerFoto(cuerpo.foto);
        if (imagen.error) return res.status(400).json({ error: imagen.error });
        try {
            const orden = vacio(cuerpo.ordenId) ? null : await empresaDeOrden(pool, cuerpo.ordenId);
            const tecnico = await pool.query('SELECT nombre FROM tecnicos WHERE id = $1', [req.usuario.id]);
            const nuevo = await pool.query(
                `INSERT INTO gastos (id_cliente, orden_id, tecnico_id, tecnico_nombre, empresa_nombre, vehiculo, km_inicio, km_fin,
                                     tipo, monto, descripcion, foto, foto_tipo, creado_en)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, COALESCE($14, now()))
                 ON CONFLICT (id_cliente) DO NOTHING RETURNING id`,
                [
                    identificador, orden ? orden.id : null, req.usuario.id, tecnico.rows[0] ? tecnico.rows[0].nombre : null,
                    orden ? orden.razon_social : texto(cuerpo.cliente, 150), texto(cuerpo.vehiculo, 60), kmInicio, kmFin,
                    tipo, monto, texto(cuerpo.descripcion, 500), imagen.foto, imagen.tipo, momentoDeLaApp(cuerpo.creadoEn),
                ]
            );
            res.json({ ok: true, id: nuevo.rows[0] ? nuevo.rows[0].id : null, yaExistia: !nuevo.rows[0] });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar el gasto' });
        }
    });

    app.get('/api/gastos', usuarioDelPanel, async (req, res) => {
        const { donde, valores } = filtrosDeGastos(req.query);
        try {
            const filas = await pool.query(`${SELECT_GASTO} ${donde} ORDER BY g.creado_en DESC LIMIT 1000`, valores);
            res.json({ tipos: TIPOS_GASTO, gastos: filas.rows });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudieron leer los gastos' });
        }
    });

    // Planilla para Administración (se abre con Excel). Separador ";" como usa Excel en español.
    app.get('/api/gastos/planilla', usuarioDelPanel, async (req, res) => {
        const { donde, valores } = filtrosDeGastos(req.query);
        try {
            const filas = await pool.query(`${SELECT_GASTO} ${donde} ORDER BY g.creado_en`, valores);
            const encabezado = ['Fecha', 'Técnico', 'Cliente', 'Orden', 'Vehículo', 'Km inicio', 'Km fin', 'Km recorridos', 'Tipo', 'Monto', 'Detalle', 'Revisado'];
            const lineas = filas.rows.map((g) => [
                fechaArgentina(g.dia), g.tecnico, g.empresa, g.orden_id ? `#${g.orden_id}` : '', g.vehiculo, g.km_inicio, g.km_fin,
                g.km_inicio !== null && g.km_fin !== null ? g.km_fin - g.km_inicio : '',
                g.tipo, g.monto === null ? '' : String(g.monto).replace('.', ','), g.descripcion, g.revisado ? 'Sí' : 'No',
            ].map(celdaCsv).join(';'));
            res.setHeader('Content-Type', 'text/csv; charset=utf-8');
            res.setHeader('Content-Disposition', `attachment; filename="gastos_${hoyISO()}.csv"`);
            res.send('﻿' + [encabezado.join(';'), ...lineas].join('\r\n'));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo armar la planilla' });
        }
    });

    app.get('/api/gastos/:id/foto', usuarioDelPanel, async (req, res) => {
        const id = entero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Gasto inválido' });
        try {
            const fila = await pool.query('SELECT foto, foto_tipo FROM gastos WHERE id = $1', [id]);
            if (!fila.rows[0] || !fila.rows[0].foto) return res.status(404).json({ error: 'Este gasto no tiene foto' });
            res.setHeader('Content-Type', fila.rows[0].foto_tipo || 'image/jpeg');
            res.setHeader('Cache-Control', 'private, max-age=3600');
            res.send(fila.rows[0].foto);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer la foto' });
        }
    });

    app.put('/api/gastos/:id', usuarioDelPanel, async (req, res) => {
        const id = entero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Gasto inválido' });
        if (typeof (req.body && req.body.revisado) !== 'boolean') return res.status(400).json({ error: 'Indicá si está revisado' });
        try {
            const cambio = await pool.query('UPDATE gastos SET revisado = $1 WHERE id = $2', [req.body.revisado, id]);
            if (!cambio.rowCount) return res.status(404).json({ error: 'Ese gasto no existe' });
            const fila = await pool.query(`${SELECT_GASTO} WHERE g.id = $1`, [id]);
            res.json(fila.rows[0]);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo actualizar el gasto' });
        }
    });

    // ================= VENCIMIENTOS =================
    // El técnico lo anota durante la visita (por ejemplo, al hacer el control de extintores).
    app.post('/api/vencimientos', soloTecnico, async (req, res) => {
        const cuerpo = req.body || {};
        const identificador = idDeLaApp(cuerpo.idCliente);
        if (!identificador) return res.status(400).json({ error: 'Falta el identificador del vencimiento' });
        const descripcion = texto(cuerpo.descripcion, 300);
        if (!descripcion) return res.status(400).json({ error: 'Escribí qué es lo que vence' });
        const vence = fechaValida(cuerpo.vence);
        if (!vence) return res.status(400).json({ error: 'La fecha de vencimiento no es válida' });
        const cantidad = vacio(cuerpo.cantidad) ? 1 : entero(cuerpo.cantidad);
        if (!(cantidad >= 1 && cantidad <= 9999)) return res.status(400).json({ error: 'La cantidad tiene que estar entre 1 y 9999' });
        try {
            const orden = vacio(cuerpo.ordenId) ? null : await empresaDeOrden(pool, cuerpo.ordenId);
            const empresa = orden && orden.empresa_id ? { id: orden.empresa_id, razon_social: orden.razon_social } : await empresaPorNombre(pool, cuerpo.cliente);
            const tecnico = await pool.query('SELECT nombre FROM tecnicos WHERE id = $1', [req.usuario.id]);
            const nuevo = await pool.query(
                `INSERT INTO vencimientos (id_cliente, empresa_id, empresa_nombre, orden_id, tecnico_id, descripcion, cantidad, vence, creado_por)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) ON CONFLICT (id_cliente) DO NOTHING RETURNING id`,
                [
                    identificador, empresa ? empresa.id : null, empresa ? empresa.razon_social : texto(cuerpo.cliente, 150),
                    orden ? orden.id : null, req.usuario.id, descripcion, cantidad, vence, tecnico.rows[0] ? tecnico.rows[0].nombre : null,
                ]
            );
            res.json({ ok: true, id: nuevo.rows[0] ? nuevo.rows[0].id : null, yaExistia: !nuevo.rows[0] });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar el vencimiento' });
        }
    });

    // Lo que vence pronto en los clientes del técnico (los de sus órdenes).
    app.get('/api/vencimientos/mios', soloTecnico, async (req, res) => {
        try {
            const filas = await pool.query(
                `${SELECT_VENCIMIENTO}
                 WHERE v.resuelto = false AND v.vence <= CURRENT_DATE + 120
                   AND (v.tecnico_id = $1 OR v.empresa_id IN (SELECT empresa_id FROM ordenes WHERE tecnico_id = $1 AND empresa_id IS NOT NULL))
                 ORDER BY v.vence LIMIT 200`,
                [req.usuario.id]
            );
            res.json(filas.rows);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudieron leer los vencimientos' });
        }
    });

    app.get('/api/vencimientos', usuarioDelPanel, async (req, res) => {
        const todos = req.query.todos === '1';
        try {
            const filas = await pool.query(
                `${SELECT_VENCIMIENTO} ${todos ? '' : 'WHERE v.resuelto = false'} ORDER BY v.resuelto, v.vence LIMIT 2000`
            );
            res.json({ diasAviso: DIAS_AVISO_VENCIMIENTO, vencimientos: filas.rows });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudieron leer los vencimientos' });
        }
    });

    // Desde el panel también se pueden cargar (por ejemplo, la habilitación municipal que mandó el cliente).
    app.post('/api/vencimientos/panel', usuarioDelPanel, async (req, res) => {
        const cuerpo = req.body || {};
        const descripcion = texto(cuerpo.descripcion, 300);
        if (!descripcion) return res.status(400).json({ error: 'Escribí qué es lo que vence' });
        const vence = fechaValida(cuerpo.vence);
        if (!vence) return res.status(400).json({ error: 'La fecha de vencimiento no es válida' });
        const cantidad = vacio(cuerpo.cantidad) ? 1 : entero(cuerpo.cantidad);
        if (!(cantidad >= 1 && cantidad <= 9999)) return res.status(400).json({ error: 'La cantidad tiene que estar entre 1 y 9999' });
        const nombre = texto(cuerpo.empresa, 150);
        if (!nombre) return res.status(400).json({ error: 'Elegí la empresa' });
        try {
            const empresa = await empresaPorNombre(pool, nombre);
            const autor = await pool.query('SELECT nombre FROM admins WHERE id = $1', [req.usuario.id]);
            const nuevo = await pool.query(
                `INSERT INTO vencimientos (empresa_id, empresa_nombre, descripcion, cantidad, vence, creado_por)
                 VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
                [empresa ? empresa.id : null, empresa ? empresa.razon_social : nombre, descripcion, cantidad, vence, autor.rows[0] ? autor.rows[0].nombre : null]
            );
            const fila = await pool.query(`${SELECT_VENCIMIENTO} WHERE v.id = $1`, [nuevo.rows[0].id]);
            res.json(fila.rows[0]);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar el vencimiento' });
        }
    });

    app.put('/api/vencimientos/:id', usuarioDelPanel, async (req, res) => {
        const id = entero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Vencimiento inválido' });
        const cuerpo = req.body || {};
        const sets = [];
        const valores = [];
        const poner = (sql, valor) => { valores.push(valor); sets.push(`${sql} = $${valores.length}`); };
        if (typeof cuerpo.resuelto === 'boolean') poner('resuelto', cuerpo.resuelto);
        if (cuerpo.vence !== undefined) {
            const vence = fechaValida(cuerpo.vence);
            if (!vence) return res.status(400).json({ error: 'La fecha de vencimiento no es válida' });
            poner('vence', vence);
            sets.push('avisado_en = NULL'); // con la fecha nueva se vuelve a avisar cuando corresponda
        }
        if (cuerpo.descripcion !== undefined) {
            const descripcion = texto(cuerpo.descripcion, 300);
            if (!descripcion) return res.status(400).json({ error: 'Escribí qué es lo que vence' });
            poner('descripcion', descripcion);
        }
        if (!sets.length) return res.status(400).json({ error: 'No hay nada para cambiar' });
        try {
            valores.push(id);
            const cambio = await pool.query(`UPDATE vencimientos SET ${sets.join(', ')} WHERE id = $${valores.length}`, valores);
            if (!cambio.rowCount) return res.status(404).json({ error: 'Ese vencimiento no existe' });
            const fila = await pool.query(`${SELECT_VENCIMIENTO} WHERE v.id = $1`, [id]);
            res.json(fila.rows[0]);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo actualizar el vencimiento' });
        }
    });

    app.delete('/api/vencimientos/:id', usuarioDelPanel, async (req, res) => {
        const id = entero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Vencimiento inválido' });
        try {
            const borrado = await pool.query('DELETE FROM vencimientos WHERE id = $1', [id]);
            if (!borrado.rowCount) return res.status(404).json({ error: 'Ese vencimiento no existe' });
            res.json({ ok: true });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo borrar el vencimiento' });
        }
    });

    // ================= PRESUPUESTOS PEDIDOS POR EL TÉCNICO =================
    // Lo que anotó para presupuestar y en qué quedó: así, antes de volver al cliente, sabe si ya se le mandó.
    app.get('/api/solicitudes-presupuesto/mias', soloTecnico, async (req, res) => {
        try {
            const filas = await pool.query(
                `SELECT s.id, s.id_cliente, s.descripcion, s.cantidad, s.estado, s.creada_en, s.actualizada_en, s.orden_id,
                        COALESCE(e.razon_social, s.empresa_nombre, 'Sin empresa') AS empresa,
                        ult.estado AS estado_presupuesto, ult.numero, ult.version,
                        to_char(ult.fecha_envio, 'YYYY-MM-DD') AS fecha_envio
                 FROM solicitudes_presupuesto s
                 LEFT JOIN empresas e ON e.id = s.empresa_id
                 LEFT JOIN LATERAL (
                     SELECT p.estado, p.numero, p.version, p.fecha_envio
                     FROM presupuesto_solicitudes ps
                     JOIN presupuestos p0 ON p0.id = ps.presupuesto_id
                     JOIN presupuestos p ON p.numero = p0.numero
                     WHERE ps.solicitud_id = s.id
                     ORDER BY p.version DESC, p.id DESC
                     LIMIT 1
                 ) ult ON true
                 WHERE s.tecnico_id = $1
                   AND (s.creada_en > now() - interval '180 days' OR s.estado IN ('Nueva', 'En presupuesto'))
                 ORDER BY s.creada_en DESC
                 LIMIT 300`,
                [req.usuario.id]
            );
            res.json(filas.rows.map((fila) => ({
                ...fila,
                estado_visible: estadoParaTecnico(fila.estado, fila.estado_presupuesto),
                presupuesto: fila.numero ? `N° ${fila.numero}${fila.version > 1 ? ` act ${fila.version - 1}` : ''}` : null,
            })));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudieron leer tus pedidos de presupuesto' });
        }
    });

    // ================= ACCESO DEL CLIENTE =================
    async function estadoPortal(id, req) {
        const fila = await pool.query('SELECT id, razon_social, email, portal_token, portal_activo FROM empresas WHERE id = $1', [id]);
        const empresa = fila.rows[0];
        if (!empresa) return null;
        const raiz = raizPublica(`${req.protocol}://${req.get('host')}`);
        return {
            activo: empresa.portal_activo === true && Boolean(empresa.portal_token),
            enlace: empresa.portal_token ? `${raiz}/cliente/${empresa.portal_token}` : null,
            email: empresa.email,
            empresa: empresa.razon_social,
        };
    }

    // El acceso del cliente lo maneja también Administración (desde Informes): no es un dato comercial.
    // Busca la empresa por el nombre de su carpeta de informes ("Canteras_del_Alto" o "Canteras del Alto").
    app.get('/api/clientes/portal-por-nombre', usuarioDelPanel, async (req, res) => {
        const nombre = texto(req.query.nombre, 150);
        if (!nombre) return res.status(400).json({ error: 'Falta el nombre del cliente' });
        try {
            const fila = await pool.query(
                `SELECT id FROM empresas
                 WHERE lower(btrim(razon_social)) = lower(btrim($1))
                    OR lower(replace(coalesce(carpeta_disco_k, ''), '_', ' ')) = lower(replace(btrim($1), '_', ' '))
                 ORDER BY id LIMIT 1`,
                [nombre]
            );
            if (!fila.rows[0]) return res.status(404).json({ error: 'Ese cliente todavía no está cargado en el sistema (aparece cuando tiene su primera orden).' });
            const id = fila.rows[0].id;
            res.json({ id, ...(await estadoPortal(id, req)) });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer el acceso del cliente' });
        }
    });

    app.get('/api/clientes/:id/portal', usuarioDelPanel, async (req, res) => {
        const id = entero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Cliente inválido' });
        try {
            const estado = await estadoPortal(id, req);
            if (!estado) return res.status(404).json({ error: 'Ese cliente no existe' });
            res.json(estado);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer el acceso del cliente' });
        }
    });

    // Activar o cortar el acceso. "regenerar" cambia el enlace: el anterior deja de funcionar.
    app.post('/api/clientes/:id/portal', usuarioDelPanel, async (req, res) => {
        const id = entero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Cliente inválido' });
        const activo = req.body && req.body.activo === true;
        const regenerar = req.body && req.body.regenerar === true;
        try {
            const actual = await pool.query('SELECT portal_token FROM empresas WHERE id = $1', [id]);
            if (!actual.rows[0]) return res.status(404).json({ error: 'Ese cliente no existe' });
            const token = regenerar || (activo && !actual.rows[0].portal_token) ? tokenNuevo() : actual.rows[0].portal_token;
            await pool.query('UPDATE empresas SET portal_activo = $1, portal_token = $2 WHERE id = $3', [activo, token, id]);
            res.json(await estadoPortal(id, req));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo cambiar el acceso del cliente' });
        }
    });

    app.post('/api/clientes/:id/portal/enviar', usuarioDelPanel, async (req, res) => {
        const id = entero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Cliente inválido' });
        try {
            const estado = await estadoPortal(id, req);
            if (!estado) return res.status(404).json({ error: 'Ese cliente no existe' });
            if (!estado.activo) return res.status(400).json({ error: 'Primero activá el acceso del cliente' });
            if (!estado.email) return res.status(400).json({ error: 'Cargá el correo del cliente en su ficha' });
            const resultado = await enviarCorreo({
                para: estado.email,
                asunto: 'Tu acceso a los informes de SIMA Ambiente',
                texto: `Hola. Desde este enlace podés ver los informes de cada visita, las próximas visitas y los vencimientos:\n\n${estado.enlace}\n\nGuardalo: es personal de ${estado.empresa}.`,
                html: `<p>Hola.</p><p>Desde este enlace podés ver los informes de cada visita, las próximas visitas y los vencimientos:</p><p><a href="${estado.enlace}">${escapar(estado.enlace)}</a></p><p>Guardalo: es personal de ${escapar(estado.empresa)}.</p>`,
            });
            if (!resultado.enviado) return res.status(503).json({ error: resultado.motivo });
            res.json({ ok: true, email: estado.email });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo mandar el correo' });
        }
    });

    // La página que ve el cliente (no necesita usuario: el enlace es la llave).
    app.get('/cliente/:token', async (req, res) => {
        const noExiste = () => res.status(404).type('html').send(pagina('SIMA', '<h1>Este enlace no existe o fue desactivado</h1>'));
        if (!tokenValido(req.params.token)) return noExiste();
        try {
            const fila = await pool.query('SELECT id, razon_social FROM empresas WHERE portal_token = $1 AND portal_activo = true', [req.params.token]);
            const empresa = fila.rows[0];
            if (!empresa) return noExiste();
            const [hechas, proximas, vencimientos] = await Promise.all([
                pool.query(
                    `SELECT o.id, to_char(o.fecha_asignada, 'YYYY-MM-DD') AS fecha, o.token_informe, o.informe_pdf, o.comentarios_cierre,
                            t.nombre AS tecnico
                     FROM ordenes o LEFT JOIN tecnicos t ON t.id = o.tecnico_id
                     WHERE o.empresa_id = $1 AND o.estado = 'Completada' AND o.fecha_asignada > CURRENT_DATE - 730
                     ORDER BY o.fecha_asignada DESC, o.id DESC LIMIT 200`,
                    [empresa.id]
                ),
                pool.query(
                    `SELECT to_char(o.fecha_asignada, 'YYYY-MM-DD') AS fecha, to_char(o.hora_ejecucion, 'HH24:MI') AS desde,
                            to_char(o.hora_hasta, 'HH24:MI') AS hasta, t.nombre AS tecnico
                     FROM ordenes o LEFT JOIN tecnicos t ON t.id = o.tecnico_id
                     WHERE o.empresa_id = $1 AND o.estado IN ('Pendiente', 'En progreso') AND o.fecha_asignada >= CURRENT_DATE
                     ORDER BY o.fecha_asignada LIMIT 6`,
                    [empresa.id]
                ),
                pool.query(
                    `SELECT descripcion, cantidad, to_char(vence, 'YYYY-MM-DD') AS vence, (vence - CURRENT_DATE)::int AS dias
                     FROM vencimientos WHERE empresa_id = $1 AND resuelto = false ORDER BY vence LIMIT 100`,
                    [empresa.id]
                ),
            ]);
            const filaVisita = (visita) => {
                const hayPdf = visita.token_informe && rutaDelInforme(visita.informe_pdf);
                const informe = hayPdf ? `<a class="btn chico" href="/informe/${visita.token_informe}">Ver informe</a>` : '<span class="suave">Informe en preparación</span>';
                const nota = visita.comentarios_cierre ? `<div class="suave">${escapar(String(visita.comentarios_cierre).slice(0, 220))}${String(visita.comentarios_cierre).length > 220 ? '…' : ''}</div>` : '';
                return `<li><div><b>${fechaArgentina(visita.fecha)}</b>${visita.tecnico ? ` · ${escapar(visita.tecnico)}` : ''}${nota}</div>${informe}</li>`;
            };
            const filaProxima = (visita) => `<li><div><b>${fechaArgentina(visita.fecha)}</b>${visita.desde ? ` · ${visita.desde}${visita.hasta ? ` a ${visita.hasta}` : ''} h` : ''}${visita.tecnico ? ` · ${escapar(visita.tecnico)}` : ''}</div></li>`;
            const filaVence = (item) => {
                const clase = item.dias < 0 ? 'vencido' : item.dias <= DIAS_AVISO_VENCIMIENTO ? 'pronto' : '';
                const cuando = item.dias < 0 ? 'Vencido' : item.dias === 0 ? 'Vence hoy' : `Vence en ${item.dias} días`;
                return `<li class="${clase}"><div><b>${escapar(item.descripcion)}</b>${item.cantidad > 1 ? ` (x${item.cantidad})` : ''}<div class="suave">${fechaArgentina(item.vence)}</div></div><span>${cuando}</span></li>`;
            };
            const cuerpo = `
                <style>
                  ul{list-style:none;padding:0;margin:0 0 24px}
                  li{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:12px 0;border-bottom:1px solid #e2e2e2}
                  li.vencido span{color:#c4412e;font-weight:700} li.pronto span{color:#b7800a;font-weight:700}
                  h2{font-size:17px;margin:26px 0 6px}
                  a.btn.chico{margin:0;padding:8px 12px;font-size:14px;white-space:nowrap}
                </style>
                <h1>${escapar(empresa.razon_social)}</h1>
                <p class="suave">Informes de las visitas de SIMA Ambiente. Este enlace es personal: no lo compartas fuera de la empresa.</p>
                ${proximas.rows.length ? `<h2>Próximas visitas</h2><ul>${proximas.rows.map(filaProxima).join('')}</ul>` : ''}
                ${vencimientos.rows.length ? `<h2>Vencimientos</h2><ul>${vencimientos.rows.map(filaVence).join('')}</ul>` : ''}
                <h2>Visitas realizadas</h2>
                ${hechas.rows.length ? `<ul>${hechas.rows.map(filaVisita).join('')}</ul>` : '<p class="suave">Todavía no hay visitas registradas en el sistema.</p>'}`;
            res.setHeader('Cache-Control', 'no-store');
            res.setHeader('X-Robots-Tag', 'noindex');
            res.type('html').send(pagina(`${empresa.razon_social} · SIMA`, cuerpo));
        } catch (error) {
            console.error(error);
            res.status(500).type('html').send(pagina('SIMA', '<h1>No se pudo abrir la página</h1>'));
        }
    });
}

module.exports = { registrarRutasOperacion, avisarVencimientos, estadoParaTecnico, TIPOS_GASTO };
