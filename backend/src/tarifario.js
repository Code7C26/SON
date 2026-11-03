// Precios y costos del área comercial: inflación mensual, tarifario (honorarios de referencia),
// costos internos y los parámetros del presupuestador. Todo es solo para Comercial.
const fs = require('fs');
const path = require('path');
const { mesActual, mesValido, valorActualizado, mesesEntre } = require('./indexacion');
const { leerIPC, sincronizarIPC, estado: estadoDeLaBusqueda } = require('./ipc');
const {
    vacio, parseEntero, parseNumero, textoOpcional, textoRequerido, numeroOpcional, booleano,
} = require('./validacion');

const RUTA_SEMILLA = path.join(__dirname, '..', 'assets', 'tarifario', 'ciec_2026.json');

// Datos de la empresa que salen en el presupuesto (los de su formulario R 7.2 - 01/A) y valores de partida.
// Todo se puede cambiar desde el panel, en Precios > Parámetros.
const CONFIG_POR_DEFECTO = {
    margen_minimo: 0.2,
    margen_ideal: 0.35,
    iva: 0.21,
    proximo_numero: 3612,
    valor_modulo: 44000,
    empresa: {
        titulo: 'SIMA (Seguridad, Ingeniería y Medio Ambiente)',
        razon_social: 'SIMA AMBIENTE SRL',
        cuit: '30-71218542-9',
        direccion: 'San Juan Bosco 486 (X5186OKL) Alta Gracia, Córdoba',
        telefonos: '03547-421682',
        iva: 'Responsable Inscripto',
        celular: '0351-2420832',
        email: 'presupuestos@simaambiente.com',
        web: 'www.simaambiente.com.ar',
    },
    firma: {
        nombre: 'María Claudia Giraudo',
        cargo: 'Socio Gerente',
        empresa: 'SIMA AMBIENTE SRL',
    },
    textos: {
        codigo_formulario: 'R 7.2 - 01/A',
        forma_pago: 'Contra entrega de factura mensual',
        plazo_entrega: 'A coordinar',
        validez: 'Actualizable al momento de acreditación del pago según valor de referencia',
    },
};

// Lee la configuración (lo guardado más los valores de partida que falten).
async function leerConfiguracion(consulta) {
    const resultado = await consulta.query('SELECT clave, valor FROM configuracion_comercial');
    const guardada = Object.fromEntries(resultado.rows.map((fila) => [fila.clave, fila.valor]));
    const config = {};
    for (const [clave, porDefecto] of Object.entries(CONFIG_POR_DEFECTO)) {
        const valor = guardada[clave];
        if (porDefecto && typeof porDefecto === 'object') {
            config[clave] = { ...porDefecto, ...(valor && typeof valor === 'object' ? valor : {}) };
        } else {
            config[clave] = valor === undefined || valor === null ? porDefecto : valor;
        }
    }
    return config;
}

// Lo que ve el panel: los porcentajes como números "de persona" (20 = 20 %).
function presentarConfiguracion(config) {
    const porcentaje = (fraccion) => Math.round(Number(fraccion) * 10000) / 100;
    return {
        margenMinimo: porcentaje(config.margen_minimo),
        margenIdeal: porcentaje(config.margen_ideal),
        iva: porcentaje(config.iva),
        proximoNumero: Number(config.proximo_numero),
        valorModulo: Number(config.valor_modulo),
        empresa: config.empresa,
        firma: config.firma,
        textos: config.textos,
    };
}

async function guardarClave(consulta, clave, valor) {
    await consulta.query(
        `INSERT INTO configuracion_comercial (clave, valor) VALUES ($1, $2)
         ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor, actualizada_en = now()`,
        [clave, JSON.stringify(valor)]
    );
}

// Al arrancar: deja los valores de partida de la configuración y, la primera vez, carga el tarifario
// del archivo assets/tarifario/ciec_2026.json (después ya no se toca: lo que se edite en el panel queda).
async function sembrarComercial(pool) {
    for (const [clave, valor] of Object.entries(CONFIG_POR_DEFECTO)) {
        await pool.query('INSERT INTO configuracion_comercial (clave, valor) VALUES ($1, $2) ON CONFLICT (clave) DO NOTHING', [clave, JSON.stringify(valor)]);
    }
    const yaSembrado = await pool.query("SELECT 1 FROM configuracion_comercial WHERE clave = 'tarifario_sembrado'");
    if (yaSembrado.rowCount) return;
    if (!fs.existsSync(RUTA_SEMILLA)) return;

    const semilla = JSON.parse(fs.readFileSync(RUTA_SEMILLA, 'utf8'));
    const cliente = await pool.connect();
    try {
        await cliente.query('BEGIN');
        for (const t of semilla.tarifas || []) {
            await cliente.query(
                `INSERT INTO tarifas (familia, servicio, tramo, detalle, nota, valor_base, mes_base, indexa, modulos)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                 ON CONFLICT (familia, servicio, tramo) DO NOTHING`,
                [
                    t.familia, t.servicio, t.tramo || '', t.detalle || null, (semilla.notas || {})[t.servicio] || null,
                    t.valor_base ?? null, t.mes_base || semilla.mes_base, t.indexa !== false, t.modulos ?? null,
                ]
            );
        }
        for (const c of semilla.costos || []) {
            // Los valores de los costos internos los carga la empresa: acá solo quedan los nombres.
            await cliente.query(
                'INSERT INTO costos_internos (concepto, unidad, valor_base, mes_base, indexa) VALUES ($1, $2, NULL, $3, $4) ON CONFLICT (concepto) DO NOTHING',
                [c.concepto, c.unidad || 'unidad', semilla.mes_base, c.indexa !== false]
            );
        }
        await guardarClave(cliente, 'tarifario_sembrado', true);
        await cliente.query('COMMIT');
    } catch (error) {
        await cliente.query('ROLLBACK').catch(() => {});
        throw error;
    } finally {
        cliente.release();
    }
}

// --- Precios actualizados ---

// Precio de una tarifa en el mes pedido. origen: 'modulos' | 'indexado' | 'fijo' | 'sin_valor'.
function precioDeTarifa(tarifa, mesObjetivo, ipc, config) {
    const modulos = tarifa.modulos === null || tarifa.modulos === undefined ? null : Number(tarifa.modulos);
    if (modulos !== null) {
        return { valor: Math.round(modulos * Number(config.valor_modulo)), factor: 1, faltantes: [], origen: 'modulos' };
    }
    if (tarifa.valor_base === null || tarifa.valor_base === undefined) return { valor: null, factor: 1, faltantes: [], origen: 'sin_valor' };
    const resultado = valorActualizado(Number(tarifa.valor_base), tarifa.mes_base, mesObjetivo, ipc, tarifa.indexa);
    return { ...resultado, origen: tarifa.indexa ? 'indexado' : 'fijo' };
}

// Costo interno en el mes pedido (null si todavía no tiene valor cargado).
function valorDeCosto(costo, mesObjetivo, ipc) {
    if (costo.valor_base === null || costo.valor_base === undefined) return { valor: null, factor: 1, faltantes: [] };
    return valorActualizado(Number(costo.valor_base), costo.mes_base, mesObjetivo, ipc, costo.indexa);
}

const numeroONulo = (valor) => (valor === null || valor === undefined ? null : Number(valor));

function presentarTarifa(fila, mesObjetivo, ipc, config) {
    const precio = precioDeTarifa(fila, mesObjetivo, ipc, config);
    return {
        id: fila.id,
        familia: fila.familia,
        servicio: fila.servicio,
        tramo: fila.tramo,
        detalle: fila.detalle,
        nota: fila.nota,
        alcance: fila.alcance,
        valorBase: numeroONulo(fila.valor_base),
        mesBase: fila.mes_base,
        indexa: fila.indexa,
        modulos: numeroONulo(fila.modulos),
        activa: fila.activa,
        valorActual: precio.valor,
        origenPrecio: precio.origen,
        factor: precio.factor,
        mesesSinIPC: precio.faltantes.length,
    };
}

function presentarCosto(fila, mesObjetivo, ipc) {
    const precio = valorDeCosto(fila, mesObjetivo, ipc);
    return {
        id: fila.id,
        concepto: fila.concepto,
        unidad: fila.unidad,
        valorBase: numeroONulo(fila.valor_base),
        mesBase: fila.mes_base,
        indexa: fila.indexa,
        valorActual: precio.valor,
        factor: precio.factor,
        mesesSinIPC: precio.faltantes.length,
    };
}

// --- Validación de lo que llega del panel ---

function limpiarTarifa(cuerpo) {
    const familia = textoRequerido(cuerpo.familia, 60, 'La familia (CIEC, Colegio de Geólogos, Propio...)');
    if (familia.error) return { error: familia.error };
    const servicio = textoRequerido(cuerpo.servicio, 300, 'El nombre del servicio');
    if (servicio.error) return { error: servicio.error };
    const tramo = textoOpcional(cuerpo.tramo, 120, 'El tramo');
    const detalle = textoOpcional(cuerpo.detalle, 300, 'El detalle');
    const nota = textoOpcional(cuerpo.nota, 1000, 'La nota');
    const alcance = textoOpcional(cuerpo.alcance, 5000, 'El alcance');
    for (const parte of [tramo, detalle, nota, alcance]) if (parte.error) return { error: parte.error };
    const valorBase = numeroOpcional(cuerpo.valorBase, { minimo: 0, maximo: 1e11, etiqueta: 'El valor' });
    if (valorBase.error) return { error: valorBase.error };
    const modulos = numeroOpcional(cuerpo.modulos, { minimo: 0.01, maximo: 100000, etiqueta: 'La cantidad de módulos' });
    if (modulos.error) return { error: modulos.error };
    const mesBase = vacio(cuerpo.mesBase) ? mesActual() : String(cuerpo.mesBase).trim();
    if (!mesValido(mesBase)) return { error: 'El mes del valor tiene que tener el formato AAAA-MM (por ejemplo 2026-01)' };
    return {
        datos: {
            familia: familia.texto,
            servicio: servicio.texto,
            tramo: tramo.texto || '',
            detalle: detalle.texto,
            nota: nota.texto,
            alcance: alcance.texto,
            valor_base: valorBase.numero,
            mes_base: mesBase,
            indexa: booleano(cuerpo.indexa, true),
            modulos: modulos.numero,
            activa: booleano(cuerpo.activa, true),
        },
    };
}

function limpiarCosto(cuerpo) {
    const concepto = textoRequerido(cuerpo.concepto, 100, 'El nombre del costo');
    if (concepto.error) return { error: concepto.error };
    const unidad = textoOpcional(cuerpo.unidad, 30, 'La unidad');
    if (unidad.error) return { error: unidad.error };
    const valorBase = numeroOpcional(cuerpo.valorBase, { minimo: 0, maximo: 1e11, etiqueta: 'El valor' });
    if (valorBase.error) return { error: valorBase.error };
    const mesBase = vacio(cuerpo.mesBase) ? mesActual() : String(cuerpo.mesBase).trim();
    if (!mesValido(mesBase)) return { error: 'El mes del valor tiene que tener el formato AAAA-MM (por ejemplo 2026-01)' };
    return {
        datos: {
            concepto: concepto.texto,
            unidad: unidad.texto || 'unidad',
            valor_base: valorBase.numero,
            mes_base: mesBase,
            indexa: booleano(cuerpo.indexa, true),
        },
    };
}

// Datos de la empresa, firma y textos: solo texto, con tope de largo.
function limpiarBloque(valor, campos, etiquetas) {
    if (valor === undefined) return { saltear: true };
    if (!valor || typeof valor !== 'object' || Array.isArray(valor)) return { error: 'Los datos no tienen el formato esperado' };
    const limpio = {};
    for (const campo of campos) {
        if (valor[campo] === undefined) continue;
        const texto = textoOpcional(valor[campo], 400, etiquetas[campo]);
        if (texto.error) return { error: texto.error };
        limpio[campo] = texto.texto || '';
    }
    return { limpio };
}

const CAMPOS_EMPRESA = ['titulo', 'razon_social', 'cuit', 'direccion', 'telefonos', 'iva', 'celular', 'email', 'web'];
const ETIQUETAS_EMPRESA = {
    titulo: 'El título de la empresa', razon_social: 'La razón social', cuit: 'El CUIT', direccion: 'La dirección', telefonos: 'Los teléfonos',
    iva: 'La condición de IVA', celular: 'El celular', email: 'El correo', web: 'La página web',
};
const CAMPOS_FIRMA = ['nombre', 'cargo', 'empresa'];
const ETIQUETAS_FIRMA = { nombre: 'El nombre de quien firma', cargo: 'El cargo', empresa: 'La empresa de la firma' };
const CAMPOS_TEXTOS = ['codigo_formulario', 'forma_pago', 'plazo_entrega', 'validez'];
const ETIQUETAS_TEXTOS = { codigo_formulario: 'El código del formulario', forma_pago: 'La forma de pago', plazo_entrega: 'El plazo de entrega', validez: 'La validez de la oferta' };

function registrarRutasTarifario(app, { pool, soloComercial }) {
    // ---------- Inflación ----------
    app.get('/api/ipc', soloComercial, async (req, res) => {
        try {
            const resultado = await pool.query('SELECT mes, variacion, fuente, actualizada_en FROM ipc_mensual ORDER BY mes DESC LIMIT 60');
            res.json({
                meses: resultado.rows.map((fila) => ({
                    mes: fila.mes,
                    porcentaje: Math.round(Number(fila.variacion) * 10000) / 100,
                    fuente: fila.fuente,
                    actualizadaEn: fila.actualizada_en,
                })),
                busqueda: estadoDeLaBusqueda(),
            });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer la inflación' });
        }
    });

    app.post('/api/ipc/sincronizar', soloComercial, async (req, res) => {
        const resultado = await sincronizarIPC(pool);
        if (!resultado.ok) return res.status(502).json({ error: `No se pudo traer la inflación del INDEC: ${resultado.error}` });
        res.json(resultado);
    });

    app.put('/api/ipc/:mes', soloComercial, async (req, res) => {
        const mes = String(req.params.mes);
        if (!mesValido(mes)) return res.status(400).json({ error: 'El mes tiene que tener el formato AAAA-MM' });
        const porcentaje = parseNumero(req.body && req.body.porcentaje);
        if (Number.isNaN(porcentaje) || porcentaje < -50 || porcentaje > 100) return res.status(400).json({ error: 'La inflación tiene que ser un número de porcentaje, por ejemplo 2,1' });
        try {
            await pool.query(
                `INSERT INTO ipc_mensual (mes, variacion, fuente) VALUES ($1, $2, 'Manual')
                 ON CONFLICT (mes) DO UPDATE SET variacion = EXCLUDED.variacion, fuente = 'Manual', actualizada_en = now()`,
                [mes, Math.round(porcentaje * 1e4) / 1e6]
            );
            res.json({ mes, porcentaje, fuente: 'Manual' });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar la inflación' });
        }
    });

    app.delete('/api/ipc/:mes', soloComercial, async (req, res) => {
        const mes = String(req.params.mes);
        if (!mesValido(mes)) return res.status(400).json({ error: 'El mes tiene que tener el formato AAAA-MM' });
        try {
            const borrado = await pool.query('DELETE FROM ipc_mensual WHERE mes = $1', [mes]);
            if (!borrado.rowCount) return res.status(404).json({ error: 'Ese mes no tiene inflación cargada' });
            res.json({ ok: true });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo borrar la inflación' });
        }
    });

    // ---------- Tarifario ----------
    app.get('/api/tarifas', soloComercial, async (req, res) => {
        const mes = vacio(req.query.mes) ? mesActual() : String(req.query.mes);
        if (!mesValido(mes)) return res.status(400).json({ error: 'El mes tiene que tener el formato AAAA-MM' });
        try {
            const [filas, ipc, config] = await Promise.all([
                pool.query('SELECT * FROM tarifas ORDER BY familia, id'),
                leerIPC(pool),
                leerConfiguracion(pool),
            ]);
            const tarifas = filas.rows.map((fila) => presentarTarifa(fila, mes, ipc, config));
            const mesMasViejo = filas.rows.filter((f) => f.indexa && f.modulos === null && f.valor_base !== null).map((f) => f.mes_base).sort()[0];
            const mesesSinIPC = mesMasViejo ? mesesEntre(mesMasViejo, mes).filter((m) => ipc[m] === undefined) : [];
            res.json({
                mes,
                valorModulo: Number(config.valor_modulo),
                mesesSinIPC,
                familias: [...new Set(tarifas.map((t) => t.familia))],
                tarifas,
            });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer el tarifario' });
        }
    });

    app.post('/api/tarifas', soloComercial, async (req, res) => {
        const limpio = limpiarTarifa(req.body || {});
        if (limpio.error) return res.status(400).json({ error: limpio.error });
        const d = limpio.datos;
        try {
            const nueva = await pool.query(
                `INSERT INTO tarifas (familia, servicio, tramo, detalle, nota, alcance, valor_base, mes_base, indexa, modulos, activa)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) RETURNING *`,
                [d.familia, d.servicio, d.tramo, d.detalle, d.nota, d.alcance, d.valor_base, d.mes_base, d.indexa, d.modulos, d.activa]
            );
            const [ipc, config] = await Promise.all([leerIPC(pool), leerConfiguracion(pool)]);
            res.json(presentarTarifa(nueva.rows[0], mesActual(), ipc, config));
        } catch (error) {
            if (error.code === '23505') return res.status(409).json({ error: 'Ya existe esa tarifa (misma familia, servicio y tramo)' });
            console.error(error);
            res.status(500).json({ error: 'No se pudo crear la tarifa' });
        }
    });

    app.put('/api/tarifas/:id', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Tarifa inválida' });
        const limpio = limpiarTarifa(req.body || {});
        if (limpio.error) return res.status(400).json({ error: limpio.error });
        const d = limpio.datos;
        try {
            const cambio = await pool.query(
                `UPDATE tarifas SET familia = $1, servicio = $2, tramo = $3, detalle = $4, nota = $5, alcance = $6, valor_base = $7,
                                    mes_base = $8, indexa = $9, modulos = $10, activa = $11, actualizada_en = now()
                 WHERE id = $12 RETURNING *`,
                [d.familia, d.servicio, d.tramo, d.detalle, d.nota, d.alcance, d.valor_base, d.mes_base, d.indexa, d.modulos, d.activa, id]
            );
            if (!cambio.rows[0]) return res.status(404).json({ error: 'Esa tarifa no existe' });
            const [ipc, config] = await Promise.all([leerIPC(pool), leerConfiguracion(pool)]);
            res.json(presentarTarifa(cambio.rows[0], mesActual(), ipc, config));
        } catch (error) {
            if (error.code === '23505') return res.status(409).json({ error: 'Ya existe esa tarifa (misma familia, servicio y tramo)' });
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar la tarifa' });
        }
    });

    app.delete('/api/tarifas/:id', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Tarifa inválida' });
        try {
            const borrada = await pool.query('DELETE FROM tarifas WHERE id = $1', [id]);
            if (!borrada.rowCount) return res.status(404).json({ error: 'Esa tarifa no existe' });
            res.json({ ok: true });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo borrar la tarifa' });
        }
    });

    // ---------- Costos internos ----------
    app.get('/api/costos', soloComercial, async (req, res) => {
        const mes = vacio(req.query.mes) ? mesActual() : String(req.query.mes);
        if (!mesValido(mes)) return res.status(400).json({ error: 'El mes tiene que tener el formato AAAA-MM' });
        try {
            const [filas, ipc] = await Promise.all([pool.query('SELECT * FROM costos_internos ORDER BY id'), leerIPC(pool)]);
            res.json({ mes, costos: filas.rows.map((fila) => presentarCosto(fila, mes, ipc)) });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudieron leer los costos' });
        }
    });

    app.post('/api/costos', soloComercial, async (req, res) => {
        const limpio = limpiarCosto(req.body || {});
        if (limpio.error) return res.status(400).json({ error: limpio.error });
        const d = limpio.datos;
        try {
            const nuevo = await pool.query(
                'INSERT INTO costos_internos (concepto, unidad, valor_base, mes_base, indexa) VALUES ($1, $2, $3, $4, $5) RETURNING *',
                [d.concepto, d.unidad, d.valor_base, d.mes_base, d.indexa]
            );
            res.json(presentarCosto(nuevo.rows[0], mesActual(), await leerIPC(pool)));
        } catch (error) {
            if (error.code === '23505') return res.status(409).json({ error: 'Ya existe un costo con ese nombre' });
            console.error(error);
            res.status(500).json({ error: 'No se pudo crear el costo' });
        }
    });

    app.put('/api/costos/:id', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Costo inválido' });
        const limpio = limpiarCosto(req.body || {});
        if (limpio.error) return res.status(400).json({ error: limpio.error });
        const d = limpio.datos;
        try {
            const cambio = await pool.query(
                `UPDATE costos_internos SET concepto = $1, unidad = $2, valor_base = $3, mes_base = $4, indexa = $5, actualizada_en = now()
                 WHERE id = $6 RETURNING *`,
                [d.concepto, d.unidad, d.valor_base, d.mes_base, d.indexa, id]
            );
            if (!cambio.rows[0]) return res.status(404).json({ error: 'Ese costo no existe' });
            res.json(presentarCosto(cambio.rows[0], mesActual(), await leerIPC(pool)));
        } catch (error) {
            if (error.code === '23505') return res.status(409).json({ error: 'Ya existe un costo con ese nombre' });
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar el costo' });
        }
    });

    app.delete('/api/costos/:id', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Costo inválido' });
        try {
            const borrado = await pool.query('DELETE FROM costos_internos WHERE id = $1', [id]);
            if (!borrado.rowCount) return res.status(404).json({ error: 'Ese costo no existe' });
            res.json({ ok: true });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo borrar el costo' });
        }
    });

    // ---------- Parámetros del presupuestador ----------
    app.get('/api/comercial/config', soloComercial, async (req, res) => {
        try {
            res.json(presentarConfiguracion(await leerConfiguracion(pool)));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer la configuración' });
        }
    });

    app.put('/api/comercial/config', soloComercial, async (req, res) => {
        const cuerpo = req.body || {};
        const cambios = {};
        const actual = await leerConfiguracion(pool).catch(() => null);
        if (!actual) return res.status(500).json({ error: 'No se pudo leer la configuración' });

        for (const [campo, clave, etiqueta, maximo] of [
            ['margenMinimo', 'margen_minimo', 'El margen mínimo', 1000],
            ['margenIdeal', 'margen_ideal', 'El margen ideal', 1000],
            ['iva', 'iva', 'El IVA', 100],
        ]) {
            if (cuerpo[campo] === undefined) continue;
            const valor = numeroOpcional(cuerpo[campo], { minimo: 0, maximo, etiqueta });
            if (valor.error || valor.numero === null) return res.status(400).json({ error: valor.error || `${etiqueta} tiene que ser un número` });
            cambios[clave] = Math.round(valor.numero * 100) / 10000;
        }
        const minimo = cambios.margen_minimo ?? Number(actual.margen_minimo);
        const ideal = cambios.margen_ideal ?? Number(actual.margen_ideal);
        if (ideal < minimo) return res.status(400).json({ error: 'El margen ideal no puede ser menor que el mínimo' });

        if (cuerpo.valorModulo !== undefined) {
            const valor = numeroOpcional(cuerpo.valorModulo, { minimo: 0, maximo: 1e9, etiqueta: 'El valor del módulo' });
            if (valor.error || valor.numero === null) return res.status(400).json({ error: valor.error || 'El valor del módulo tiene que ser un número' });
            cambios.valor_modulo = valor.numero;
        }
        if (cuerpo.proximoNumero !== undefined) {
            const numero = parseEntero(cuerpo.proximoNumero);
            if (!(numero >= 1)) return res.status(400).json({ error: 'El próximo número de presupuesto tiene que ser un número entero' });
            const maximo = await pool.query('SELECT COALESCE(MAX(numero), 0)::int AS numero FROM presupuestos');
            if (numero <= maximo.rows[0].numero) return res.status(400).json({ error: `Ya hay presupuestos hasta el número ${maximo.rows[0].numero}: el próximo tiene que ser mayor` });
            cambios.proximo_numero = numero;
        }
        for (const [campo, clave, campos, etiquetas] of [
            ['empresa', 'empresa', CAMPOS_EMPRESA, ETIQUETAS_EMPRESA],
            ['firma', 'firma', CAMPOS_FIRMA, ETIQUETAS_FIRMA],
            ['textos', 'textos', CAMPOS_TEXTOS, ETIQUETAS_TEXTOS],
        ]) {
            const bloque = limpiarBloque(cuerpo[campo], campos, etiquetas);
            if (bloque.error) return res.status(400).json({ error: bloque.error });
            if (!bloque.saltear) cambios[clave] = { ...actual[clave], ...bloque.limpio };
        }
        if (!Object.keys(cambios).length) return res.status(400).json({ error: 'No hay nada para cambiar' });

        try {
            for (const [clave, valor] of Object.entries(cambios)) await guardarClave(pool, clave, valor);
            res.json(presentarConfiguracion(await leerConfiguracion(pool)));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar la configuración' });
        }
    });
}

module.exports = {
    CONFIG_POR_DEFECTO, leerConfiguracion, presentarConfiguracion, guardarClave, sembrarComercial,
    precioDeTarifa, valorDeCosto, registrarRutasTarifario,
};
