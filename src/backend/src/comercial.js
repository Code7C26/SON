// Área comercial: lo que los técnicos anotan para presupuestar y las fichas de los clientes.
// Las rutas viven acá aparte para que index.js no siga creciendo.
const { emailValido } = require('./auth');

// "Enviada" y "Aprobada" sirven para lo que se presupuesta por fuera del presupuestador (por WhatsApp o
// mail): así el técnico igual ve en qué quedó. Si la nota está en un presupuesto, manda el de ese presupuesto.
const ESTADOS_SOLICITUD = ['Nueva', 'En presupuesto', 'Presupuestada', 'Enviada', 'Aprobada', 'Descartada'];
const ESTADOS_ABIERTOS = ['Nueva', 'En presupuesto'];
const MAX_FOTO_BYTES = 4 * 1024 * 1024;
const MAX_DESCRIPCION = 500;
const MAX_NOTA = 1000;

// Nombre de carpeta que se le da a una empresa nueva (el de los informes sale del nombre del cliente).
function carpetaDeEmpresa(nombre) {
    const carpeta = String(nombre).replace(/\s+/g, '_').replace(/[^a-zA-Z0-9_-]/g, '');
    return carpeta || 'cliente';
}

// Convierte "12" o 12 en número entero; cualquier otra cosa (vacío, "abc", 1.5) da NaN.
function parseEntero(valor) {
    if (typeof valor === 'number') return Number.isInteger(valor) ? valor : NaN;
    if (typeof valor === 'string' && /^\d{1,9}$/.test(valor.trim())) return Number(valor.trim());
    return NaN;
}

function vacio(valor) {
    return valor === undefined || valor === null || valor === '';
}

function hayEncabezadoDeImagen(bytes) {
    if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
    if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
    if (bytes.length >= 12 && bytes.subarray(0, 4).toString('latin1') === 'RIFF' && bytes.subarray(8, 12).toString('latin1') === 'WEBP') return 'image/webp';
    return null;
}

// La app manda la foto como "data:image/jpeg;base64,...". Se verifica que de verdad sea una imagen.
function leerFoto(valor) {
    if (vacio(valor)) return { foto: null, tipo: null };
    const texto = String(valor);
    const coma = texto.indexOf(',');
    if (coma < 0 || !/^data:image\/(jpeg|png|webp);base64$/.test(texto.slice(0, coma))) {
        return { error: 'La foto no es una imagen válida' };
    }
    const bytes = Buffer.from(texto.slice(coma + 1), 'base64');
    if (!bytes.length) return { error: 'La foto está vacía' };
    if (bytes.length > MAX_FOTO_BYTES) return { error: 'La foto es demasiado grande (máximo 4 MB)' };
    const tipo = hayEncabezadoDeImagen(bytes);
    if (!tipo) return { error: 'La foto no es una imagen válida' };
    return { foto: bytes, tipo };
}

// La hora en que el técnico hizo la nota (puede ser anterior si estaba sin internet).
function fechaDeLaNota(valor) {
    if (vacio(valor)) return null;
    const fecha = new Date(valor);
    if (Number.isNaN(fecha.getTime())) return null;
    const ahora = Date.now();
    if (fecha.getTime() > ahora + 5 * 60 * 1000 || fecha.getTime() < ahora - 60 * 24 * 60 * 60 * 1000) return null;
    return fecha;
}

function validarDescripcion(valor) {
    const texto = String(valor ?? '').trim();
    if (!texto) return { error: 'Escribí qué falta presupuestar' };
    if (texto.length > MAX_DESCRIPCION) return { error: `La descripción es muy larga (máximo ${MAX_DESCRIPCION} letras)` };
    return { texto };
}

function validarCantidad(valor) {
    if (vacio(valor)) return { cantidad: 1 };
    const cantidad = parseEntero(valor);
    if (!(cantidad >= 1 && cantidad <= 9999)) return { error: 'La cantidad tiene que estar entre 1 y 9999' };
    return { cantidad };
}

// CUIT argentino: 11 dígitos con dígito verificador. Se guarda como XX-XXXXXXXX-X.
function normalizarCuit(valor) {
    const digitos = String(valor ?? '').replace(/\D/g, '');
    if (!digitos) return { cuit: null };
    if (digitos.length !== 11) return { error: 'El CUIT tiene que tener 11 números' };
    const pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
    const suma = pesos.reduce((total, peso, i) => total + peso * Number(digitos[i]), 0);
    let verificador = 11 - (suma % 11);
    if (verificador === 11) verificador = 0;
    if (verificador === 10 || verificador !== Number(digitos[10])) return { error: 'El CUIT no es válido, revisá los números' };
    return { cuit: `${digitos.slice(0, 2)}-${digitos.slice(2, 10)}-${digitos.slice(10)}` };
}

function textoOpcional(valor, maximo, etiqueta) {
    const texto = String(valor ?? '').trim();
    if (texto.length > maximo) return { error: `${etiqueta} es demasiado largo (máximo ${maximo} letras)` };
    return { texto: texto || null };
}

// Valida y ordena los datos de una ficha de cliente.
function limpiarCliente(cuerpo) {
    const razon = String(cuerpo.razon_social ?? '').trim().replace(/\s+/g, ' ');
    if (razon.length < 2) return { error: 'Ingresá el nombre de la empresa' };
    if (razon.length > 150) return { error: 'El nombre de la empresa es demasiado largo' };

    const direccion = textoOpcional(cuerpo.direccion_principal, 255, 'La dirección');
    const contacto = textoOpcional(cuerpo.contacto, 100, 'El nombre de contacto');
    const telefono = textoOpcional(cuerpo.telefono, 60, 'El teléfono');
    const notas = textoOpcional(cuerpo.notas, 2000, 'La nota');
    for (const parte of [direccion, contacto, telefono, notas]) if (parte.error) return { error: parte.error };

    const actividad = textoOpcional(cuerpo.actividad, 100, 'La actividad');
    const provincia = textoOpcional(cuerpo.provincia, 100, 'La provincia');
    const departamento = textoOpcional(cuerpo.departamento, 100, 'El departamento');
    const ciudad = textoOpcional(cuerpo.ciudad, 100, 'La ciudad');
    for (const parte of [actividad, provincia, departamento, ciudad]) if (parte.error) return { error: parte.error };

    const email = String(cuerpo.email ?? '').trim().toLowerCase();
    if (email && !emailValido(email)) return { error: 'El correo de contacto no es válido' };

    const cuit = normalizarCuit(cuerpo.cuit);
    if (cuit.error) return { error: cuit.error };

    // Riesgo de incendio (R1 a R7, como en el Decreto 351/79) y categoría de la empresa (A, B o C).
    const riesgo = String(cuerpo.riesgo ?? '').trim().toUpperCase();
    if (riesgo && !/^R[1-7]$/.test(riesgo)) return { error: 'El riesgo tiene que ser de R1 a R7' };
    const categoria = String(cuerpo.categoria ?? '').trim().toUpperCase();
    if (categoria && !['A', 'B', 'C'].includes(categoria)) return { error: 'La categoría tiene que ser A, B o C' };

    return {
        datos: {
            razon_social: razon,
            direccion_principal: direccion.texto,
            contacto: contacto.texto,
            telefono: telefono.texto,
            email: email || null,
            cuit: cuit.cuit,
            notas: notas.texto,
            actividad: actividad.texto,
            riesgo: riesgo || null,
            categoria: categoria || null,
            provincia: provincia.texto,
            departamento: departamento.texto,
            ciudad: ciudad.texto,
        },
    };
}

const SELECT_SOLICITUD = `
    SELECT s.id, s.descripcion, s.cantidad, s.estado, s.nota_comercial, s.creada_en, s.actualizada_en,
           s.orden_id, s.tecnico_id,
           COALESCE(t.nombre, s.tecnico_nombre) AS tecnico,
           s.empresa_id,
           COALESCE(e.razon_social, s.empresa_nombre, 'Sin empresa') AS empresa,
           (s.foto IS NOT NULL) AS tiene_foto
    FROM solicitudes_presupuesto s
    LEFT JOIN empresas e ON e.id = s.empresa_id
    LEFT JOIN tecnicos t ON t.id = s.tecnico_id
`;

const SELECT_CLIENTE = `
    SELECT e.id, e.razon_social, e.direccion_principal, e.contacto, e.telefono, e.email, e.cuit, e.notas,
           e.actividad, e.riesgo, e.categoria, e.provincia, e.departamento, e.ciudad,
           (SELECT COUNT(*)::int FROM ordenes o WHERE o.empresa_id = e.id) AS ordenes,
           (SELECT COUNT(*)::int FROM solicitudes_presupuesto s
             WHERE s.empresa_id = e.id AND s.estado = ANY($1)) AS por_presupuestar
    FROM empresas e
`;

function registrarRutasComercial(app, { pool, soloComercial, usuarioDelPanel, soloTecnico }) {
    // --- Técnico: anota algo que falta presupuestar durante la visita ---
    app.post('/api/solicitudes-presupuesto', soloTecnico, async (req, res) => {
        const { idCliente, ordenId, cliente, descripcion, cantidad, foto, creadaEn } = req.body || {};
        // El identificador lo genera la app: si la respuesta se pierde por falta de señal y la nota
        // se reenvía, el servidor reconoce que ya la tiene y no la duplica.
        const identificador = String(idCliente || '');
        if (!/^[A-Za-z0-9_-]{8,64}$/.test(identificador)) return res.status(400).json({ error: 'Falta el identificador de la nota' });
        const texto = validarDescripcion(descripcion);
        if (texto.error) return res.status(400).json({ error: texto.error });
        const cant = validarCantidad(cantidad);
        if (cant.error) return res.status(400).json({ error: cant.error });
        const imagen = leerFoto(foto);
        if (imagen.error) return res.status(400).json({ error: imagen.error });
        if (!vacio(ordenId) && Number.isNaN(parseEntero(ordenId))) return res.status(400).json({ error: 'Orden inválida' });

        try {
            let empresaId = null;
            let empresaNombre = String(cliente || '').trim().slice(0, 150) || null;
            let ordenValida = null;
            if (!vacio(ordenId)) {
                const orden = await pool.query(
                    `SELECT o.id, o.empresa_id, e.razon_social
                     FROM ordenes o LEFT JOIN empresas e ON e.id = o.empresa_id
                     WHERE o.id = $1`,
                    [parseEntero(ordenId)]
                );
                if (orden.rows[0]) {
                    ordenValida = orden.rows[0].id;
                    empresaId = orden.rows[0].empresa_id;
                    empresaNombre = orden.rows[0].razon_social || empresaNombre;
                }
            }
            if (!empresaId && empresaNombre) {
                const porNombre = await pool.query(
                    'SELECT id, razon_social FROM empresas WHERE lower(btrim(razon_social)) = lower(btrim($1)) ORDER BY id LIMIT 1',
                    [empresaNombre]
                );
                if (porNombre.rows[0]) {
                    empresaId = porNombre.rows[0].id;
                    empresaNombre = porNombre.rows[0].razon_social;
                }
            }
            const tecnico = await pool.query('SELECT nombre FROM tecnicos WHERE id = $1', [req.usuario.id]);

            const nueva = await pool.query(
                `INSERT INTO solicitudes_presupuesto
                    (id_cliente, empresa_id, empresa_nombre, orden_id, tecnico_id, tecnico_nombre,
                     descripcion, cantidad, foto, foto_tipo, creada_en)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, COALESCE($11, now()))
                 ON CONFLICT (id_cliente) DO NOTHING
                 RETURNING id`,
                [
                    identificador, empresaId, empresaNombre, ordenValida, req.usuario.id,
                    tecnico.rows[0] ? tecnico.rows[0].nombre : null,
                    texto.texto, cant.cantidad, imagen.foto, imagen.tipo, fechaDeLaNota(creadaEn),
                ]
            );
            if (!nueva.rows[0]) {
                const existente = await pool.query('SELECT id FROM solicitudes_presupuesto WHERE id_cliente = $1', [identificador]);
                return res.json({ ok: true, id: existente.rows[0] ? existente.rows[0].id : null, yaExistia: true });
            }
            res.json({ ok: true, id: nueva.rows[0].id, yaExistia: false });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar la nota' });
        }
    });

    // --- Comercial / administrador: bandeja "Por presupuestar" ---
    app.get('/api/solicitudes-presupuesto', soloComercial, async (req, res) => {
        const { estado, empresaId } = req.query;
        const condiciones = [];
        const valores = [];
        if (estado === 'abiertas') {
            valores.push(ESTADOS_ABIERTOS);
            condiciones.push(`s.estado = ANY($${valores.length})`);
        } else if (typeof estado === 'string' && estado) {
            if (!ESTADOS_SOLICITUD.includes(estado)) return res.status(400).json({ error: 'Estado inválido' });
            valores.push(estado);
            condiciones.push(`s.estado = $${valores.length}`);
        }
        if (!vacio(empresaId)) {
            const id = parseEntero(empresaId);
            if (Number.isNaN(id)) return res.status(400).json({ error: 'Empresa inválida' });
            valores.push(id);
            condiciones.push(`s.empresa_id = $${valores.length}`);
        }
        try {
            const donde = condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '';
            const resultado = await pool.query(`${SELECT_SOLICITUD} ${donde} ORDER BY s.creada_en DESC, s.id DESC`, valores);
            res.json(resultado.rows);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer la bandeja' });
        }
    });

    // Cantidad en cada estado (el menú del panel muestra cuántas hay nuevas).
    app.get('/api/solicitudes-presupuesto/resumen', soloComercial, async (req, res) => {
        try {
            const resultado = await pool.query(`
                SELECT COUNT(*) FILTER (WHERE estado = 'Nueva')::int AS nuevas,
                       COUNT(*) FILTER (WHERE estado = 'En presupuesto')::int AS en_presupuesto,
                       COUNT(*) FILTER (WHERE estado = 'Presupuestada')::int AS presupuestadas,
                       COUNT(*) FILTER (WHERE estado = 'Descartada')::int AS descartadas
                FROM solicitudes_presupuesto
            `);
            res.json(resultado.rows[0]);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo calcular el resumen' });
        }
    });

    app.get('/api/solicitudes-presupuesto/:id/foto', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Nota inválida' });
        try {
            const resultado = await pool.query('SELECT foto, foto_tipo FROM solicitudes_presupuesto WHERE id = $1', [id]);
            const fila = resultado.rows[0];
            if (!fila || !fila.foto) return res.status(404).json({ error: 'Esta nota no tiene foto' });
            res.setHeader('Content-Type', fila.foto_tipo || 'image/jpeg');
            res.setHeader('Cache-Control', 'private, max-age=3600');
            res.send(fila.foto);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer la foto' });
        }
    });

    app.put('/api/solicitudes-presupuesto/:id', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Nota inválida' });
        const cuerpo = req.body || {};
        const asignaciones = [];
        const valores = [];
        const agregar = (columna, valor) => {
            valores.push(valor);
            asignaciones.push(`${columna} = $${valores.length}`);
        };

        if (cuerpo.estado !== undefined) {
            if (!ESTADOS_SOLICITUD.includes(cuerpo.estado)) return res.status(400).json({ error: 'Estado inválido' });
            agregar('estado', cuerpo.estado);
        }
        if (cuerpo.descripcion !== undefined) {
            const texto = validarDescripcion(cuerpo.descripcion);
            if (texto.error) return res.status(400).json({ error: texto.error });
            agregar('descripcion', texto.texto);
        }
        if (cuerpo.cantidad !== undefined) {
            const cant = validarCantidad(cuerpo.cantidad);
            if (cant.error) return res.status(400).json({ error: cant.error });
            agregar('cantidad', cant.cantidad);
        }
        if (cuerpo.nota !== undefined) {
            const nota = textoOpcional(cuerpo.nota, MAX_NOTA, 'La nota');
            if (nota.error) return res.status(400).json({ error: nota.error });
            agregar('nota_comercial', nota.texto);
        }
        if (!asignaciones.length) return res.status(400).json({ error: 'No hay nada para cambiar' });

        try {
            valores.push(id);
            const cambio = await pool.query(
                `UPDATE solicitudes_presupuesto SET ${asignaciones.join(', ')}, actualizada_en = now() WHERE id = $${valores.length}`,
                valores
            );
            if (!cambio.rowCount) return res.status(404).json({ error: 'Esa nota no existe' });
            const actualizada = await pool.query(`${SELECT_SOLICITUD} WHERE s.id = $1`, [id]);
            res.json(actualizada.rows[0]);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo actualizar la nota' });
        }
    });

    // --- Fichas de clientes (las empresas con sus datos de contacto): solo Comercial ---
    // Solo los nombres de las empresas: los usa el formulario de órdenes para sugerir clientes, así
    // que lo puede pedir también Administración. Los datos de contacto, CUIT, etc. no salen de acá.
    app.get('/api/clientes/nombres', usuarioDelPanel, async (req, res) => {
        try {
            const resultado = await pool.query('SELECT id, razon_social FROM empresas ORDER BY lower(razon_social)');
            res.json(resultado.rows);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer la lista de clientes' });
        }
    });

    app.get('/api/clientes', soloComercial, async (req, res) => {
        try {
            const resultado = await pool.query(`${SELECT_CLIENTE} ORDER BY lower(e.razon_social)`, [ESTADOS_ABIERTOS]);
            res.json(resultado.rows);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer la lista de clientes' });
        }
    });

    app.post('/api/clientes', soloComercial, async (req, res) => {
        const limpio = limpiarCliente(req.body || {});
        if (limpio.error) return res.status(400).json({ error: limpio.error });
        const d = limpio.datos;
        try {
            const repetido = await pool.query('SELECT id FROM empresas WHERE lower(btrim(razon_social)) = lower($1)', [d.razon_social]);
            if (repetido.rows.length) return res.status(409).json({ error: 'Ya existe un cliente con ese nombre' });
            const nueva = await pool.query(
                `INSERT INTO empresas (razon_social, direccion_principal, carpeta_disco_k, contacto, telefono, email, cuit, notas,
                                       actividad, riesgo, categoria, provincia, departamento, ciudad)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) RETURNING id`,
                [
                    d.razon_social, d.direccion_principal, carpetaDeEmpresa(d.razon_social), d.contacto, d.telefono, d.email, d.cuit, d.notas,
                    d.actividad, d.riesgo, d.categoria, d.provincia, d.departamento, d.ciudad,
                ]
            );
            const cliente = await pool.query(`${SELECT_CLIENTE} WHERE e.id = $2`, [ESTADOS_ABIERTOS, nueva.rows[0].id]);
            res.json(cliente.rows[0]);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo crear el cliente' });
        }
    });

    app.put('/api/clientes/:id', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Cliente inválido' });
        const limpio = limpiarCliente(req.body || {});
        if (limpio.error) return res.status(400).json({ error: limpio.error });
        const d = limpio.datos;
        try {
            const repetido = await pool.query(
                'SELECT id FROM empresas WHERE lower(btrim(razon_social)) = lower($1) AND id <> $2',
                [d.razon_social, id]
            );
            if (repetido.rows.length) return res.status(409).json({ error: 'Ya existe un cliente con ese nombre' });
            const cambio = await pool.query(
                `UPDATE empresas SET razon_social = $1, direccion_principal = $2, contacto = $3, telefono = $4,
                                     email = $5, cuit = $6, notas = $7, actividad = $8, riesgo = $9, categoria = $10,
                                     provincia = $11, departamento = $12, ciudad = $13
                 WHERE id = $14`,
                [
                    d.razon_social, d.direccion_principal, d.contacto, d.telefono, d.email, d.cuit, d.notas,
                    d.actividad, d.riesgo, d.categoria, d.provincia, d.departamento, d.ciudad, id,
                ]
            );
            if (!cambio.rowCount) return res.status(404).json({ error: 'Ese cliente no existe' });
            const cliente = await pool.query(`${SELECT_CLIENTE} WHERE e.id = $2`, [ESTADOS_ABIERTOS, id]);
            res.json(cliente.rows[0]);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar el cliente' });
        }
    });
}

module.exports = { registrarRutasComercial, carpetaDeEmpresa, ESTADOS_SOLICITUD };
