// Presupuestos: armado con precios del tarifario actualizados por inflación, cuentas, versiones
// ("act") y PDF para el cliente. Solo para Comercial.
const { aMes, mesActual, fechaDeHoy, avisoIPCFaltante, nombreDelMes } = require('./indexacion');
const { calcularPresupuesto } = require('./presupuesto_calculo');
const { leerIPC } = require('./ipc');
const { leerConfiguracion, guardarClave, precioDeTarifa, valorDeCosto } = require('./tarifario');
const { crearPresupuestoPdf } = require('./presupuesto_pdf');
const { emailValido } = require('./auth');
const {
    vacio, parseEntero, parseNumero, textoOpcional, textoRequerido, numeroOpcional, booleano, fechaValida,
} = require('./validacion');

const ESTADOS = ['Borrador', 'Enviado', 'Negociando', 'Aceptado', 'Rechazado'];
const PRIORIDADES = ['baja', 'media', 'alta'];
const MAX_ITEMS = 80;
const MAX_PARTES_COSTO = 12;

// "3611", "3611 - act", "3611 - act 2"
function etiquetaDe(numero, version) {
    if (version <= 1) return String(numero);
    return version === 2 ? `${numero} - act` : `${numero} - act ${version - 1}`;
}

const numeroONulo = (valor) => (valor === null || valor === undefined ? null : Number(valor));
const porcentaje = (fraccion) => (fraccion === null || fraccion === undefined || !Number.isFinite(fraccion) ? null : Math.round(fraccion * 10000) / 100);

// --- Validación de lo que llega del panel ---

function limpiarCliente(valor) {
    const origen = valor && typeof valor === 'object' && !Array.isArray(valor) ? valor : {};
    const campos = [
        ['razonSocial', 150, 'El nombre del cliente'], ['direccion', 255, 'El domicilio'], ['localidad', 100, 'La localidad'],
        ['provincia', 100, 'La provincia'], ['telefono', 60, 'El teléfono'], ['email', 120, 'El correo'],
        ['cuit', 20, 'El CUIT'], ['atencion', 100, 'La persona de atención'],
    ];
    const limpio = {};
    for (const [campo, maximo, etiqueta] of campos) {
        const texto = textoOpcional(origen[campo], maximo, etiqueta);
        if (texto.error) return { error: texto.error };
        limpio[campo] = texto.texto || '';
    }
    if (limpio.email && !emailValido(limpio.email.toLowerCase())) return { error: 'El correo del cliente no es válido' };
    return { cliente: limpio };
}

function limpiarParteDeCosto(parte, numeroItem) {
    if (!parte || typeof parte !== 'object') return { error: `Ítem ${numeroItem}: una parte del costo no es válida` };
    const cantidad = parseNumero(parte.cantidad);
    if (Number.isNaN(cantidad) || cantidad < 0 || cantidad > 100000) return { error: `Ítem ${numeroItem}: la cantidad del costo tiene que ser un número` };
    let costoId = null;
    if (!vacio(parte.costoId)) {
        costoId = parseEntero(parte.costoId);
        if (Number.isNaN(costoId)) return { error: `Ítem ${numeroItem}: costo inválido` };
    }
    const concepto = textoOpcional(parte.concepto, 100, 'El nombre del costo');
    if (concepto.error) return { error: `Ítem ${numeroItem}: ${concepto.error}` };
    const unitario = numeroOpcional(parte.costoUnitario, { minimo: 0, maximo: 1e10, etiqueta: 'El costo unitario' });
    if (unitario.error) return { error: `Ítem ${numeroItem}: ${unitario.error}` };
    if (costoId === null && unitario.numero === null) return { error: `Ítem ${numeroItem}: elegí un costo de la lista o escribí su valor` };
    return { parte: { costoId, concepto: concepto.texto || '', cantidad, costoUnitario: unitario.numero } };
}

function limpiarItem(item, indice) {
    const numero = indice + 1;
    if (!item || typeof item !== 'object') return { error: `El ítem ${numero} no es válido` };
    const descripcion = textoRequerido(item.descripcion, 2000, `La descripción del ítem ${numero}`);
    if (descripcion.error) return { error: descripcion.error };
    const alcance = textoOpcional(item.alcance, 5000, `El alcance del ítem ${numero}`);
    if (alcance.error) return { error: alcance.error };
    const cantidad = vacio(item.cantidad) ? 1 : parseNumero(item.cantidad);
    if (Number.isNaN(cantidad) || cantidad <= 0 || cantidad > 99999) return { error: `La cantidad del ítem ${numero} tiene que ser un número mayor a 0` };
    let tarifaId = null;
    if (!vacio(item.tarifaId)) {
        tarifaId = parseEntero(item.tarifaId);
        if (Number.isNaN(tarifaId)) return { error: `La tarifa del ítem ${numero} no es válida` };
    }
    const precioManual = numeroOpcional(item.precioManual, { minimo: 0, maximo: 1e11, etiqueta: `El precio del ítem ${numero}` });
    if (precioManual.error) return { error: precioManual.error };
    if (item.periodicidad !== undefined && !['mensual', 'unico'].includes(item.periodicidad)) return { error: `El tipo de cobro del ítem ${numero} no es válido` };
    const periodicidad = item.periodicidad === 'unico' ? 'unico' : 'mensual';
    let prorratearMeses = null;
    if (periodicidad === 'unico' && !vacio(item.prorratearMeses)) {
        prorratearMeses = parseEntero(item.prorratearMeses);
        if (Number.isNaN(prorratearMeses) || prorratearMeses < 2 || prorratearMeses > 60) return { error: `Los meses para prorratear el ítem ${numero} tienen que estar entre 2 y 60` };
    }
    const costeoBruto = item.costeo === undefined || item.costeo === null ? [] : item.costeo;
    if (!Array.isArray(costeoBruto) || costeoBruto.length > MAX_PARTES_COSTO) return { error: `El costo del ítem ${numero} tiene demasiadas partes` };
    const costeo = [];
    for (const parte of costeoBruto) {
        const limpia = limpiarParteDeCosto(parte, numero);
        if (limpia.error) return { error: limpia.error };
        costeo.push(limpia.parte);
    }
    return {
        item: {
            tarifaId,
            descripcion: descripcion.texto,
            alcance: alcance.texto,
            cantidad,
            precioManual: precioManual.numero,
            periodicidad,
            prorratearMeses,
            bonificable: booleano(item.bonificable, true),
            costeo,
        },
    };
}

function limpiarEncabezado(cuerpo, config) {
    const cliente = limpiarCliente(cuerpo.cliente);
    if (cliente.error) return { error: cliente.error };

    let empresaId = null;
    if (!vacio(cuerpo.empresaId)) {
        empresaId = parseEntero(cuerpo.empresaId);
        if (Number.isNaN(empresaId)) return { error: 'Cliente inválido' };
    }
    const hoy = fechaDeHoy();
    const fecha = vacio(cuerpo.fecha) ? hoy : String(cuerpo.fecha).trim();
    if (!fechaValida(fecha) || fecha < '2020-01-01' || fecha > fechaDeHoy(new Date(Date.now() + 366 * 24 * 3600 * 1000))) return { error: 'La fecha del presupuesto no es válida' };

    const bonificacion = numeroOpcional(cuerpo.bonificacion, { minimo: 0, maximo: 100, etiqueta: 'La bonificación' });
    if (bonificacion.error) return { error: bonificacion.error };

    const textos = {};
    for (const [campo, clave, maximo, etiqueta] of [
        ['formaPago', 'forma_pago', 200, 'La forma de pago'], ['plazoEntrega', 'plazo_entrega', 200, 'El plazo de entrega'],
        ['validez', 'validez', 300, 'La validez de la oferta'], ['referencia', null, 200, 'El valor de referencia'],
        ['observaciones', null, 3000, 'Las observaciones'],
    ]) {
        if (cuerpo[campo] === undefined && clave) {
            textos[campo] = config.textos[clave] || null;
            continue;
        }
        const texto = textoOpcional(cuerpo[campo], maximo, etiqueta);
        if (texto.error) return { error: texto.error };
        textos[campo] = texto.texto;
    }

    const itemsBrutos = cuerpo.items;
    if (!Array.isArray(itemsBrutos)) return { error: 'Faltan los ítems del presupuesto' };
    if (itemsBrutos.length > MAX_ITEMS) return { error: `Un presupuesto puede tener hasta ${MAX_ITEMS} ítems` };
    const items = [];
    for (let i = 0; i < itemsBrutos.length; i++) {
        const limpio = limpiarItem(itemsBrutos[i], i);
        if (limpio.error) return { error: limpio.error };
        items.push(limpio.item);
    }

    let solicitudIds = [];
    if (cuerpo.solicitudIds !== undefined && cuerpo.solicitudIds !== null) {
        if (!Array.isArray(cuerpo.solicitudIds) || cuerpo.solicitudIds.length > 200) return { error: 'Las notas de técnicos no son válidas' };
        solicitudIds = [...new Set(cuerpo.solicitudIds.map(parseEntero))];
        if (solicitudIds.some(Number.isNaN)) return { error: 'Las notas de técnicos no son válidas' };
    }

    return {
        datos: {
            empresaId,
            cliente: cliente.cliente,
            fecha,
            mesReferencia: aMes(fecha),
            bonificacion: (bonificacion.numero || 0) / 100,
            ...textos,
            items,
            solicitudIds,
        },
    };
}

// Completa los datos del cliente que quedaron vacíos con los de su ficha.
function completarClienteConFicha(cliente, empresa) {
    if (!empresa) return cliente;
    const deLaFicha = {
        razonSocial: empresa.razon_social, direccion: empresa.direccion_principal, localidad: empresa.ciudad, provincia: empresa.provincia,
        telefono: empresa.telefono, email: empresa.email, cuit: empresa.cuit, atencion: empresa.contacto,
    };
    const resultado = { ...cliente };
    for (const [campo, valor] of Object.entries(deLaFicha)) if (!resultado[campo] && valor) resultado[campo] = valor;
    return resultado;
}

// --- Precios: de lo que pide la persona a ítems con precio y costo resueltos ---

async function cargarCatalogos(consulta, items) {
    const idsTarifas = [...new Set(items.map((i) => i.tarifaId).filter((id) => id !== null))];
    const tarifas = new Map();
    if (idsTarifas.length) {
        const filas = await consulta.query('SELECT * FROM tarifas WHERE id = ANY($1)', [idsTarifas]);
        for (const fila of filas.rows) tarifas.set(fila.id, fila);
    }
    const costos = new Map();
    const filasCostos = await consulta.query('SELECT * FROM costos_internos');
    for (const fila of filasCostos.rows) costos.set(fila.id, fila);
    return { tarifas, costos };
}

function nombreDeTarifa(tarifa) {
    return [tarifa.familia, tarifa.servicio, tarifa.tramo].filter(Boolean).join(' · ');
}

// Devuelve los ítems con su precio (del tarifario o a mano), su costo y avisos, y los meses sin inflación.
function resolverItems(items, { mes, ipc, config, tarifas, costos }) {
    const faltantes = new Set();
    const resueltos = items.map((item, indice) => {
        const numero = indice + 1;
        const avisos = [];
        let precioUnitario = null;
        let precioOrigen = 'manual';
        let precioTarifa = null;
        let valorBase = null;
        let mesBase = null;
        let factor = 1;
        let tarifaNombre = null;
        let tarifaId = item.tarifaId;

        if (tarifaId !== null) {
            const tarifa = tarifas.get(tarifaId);
            if (!tarifa) {
                avisos.push(`La tarifa del ítem ${numero} ya no existe: escribí el precio a mano.`);
                tarifaId = null;
            } else {
                tarifaNombre = nombreDeTarifa(tarifa);
                const precio = precioDeTarifa(tarifa, mes, ipc, config);
                precioTarifa = precio.valor;
                valorBase = numeroONulo(tarifa.valor_base);
                mesBase = tarifa.mes_base;
                factor = precio.factor;
                precio.faltantes.forEach((m) => faltantes.add(m));
                if (precio.valor === null) avisos.push(`La tarifa del ítem ${numero} todavía no tiene valor cargado (el tarifario está incompleto). Escribí el precio a mano o completá el tarifario.`);
                if (item.precioManual === null) {
                    precioUnitario = precio.valor;
                    precioOrigen = 'tarifa';
                }
            }
        }
        if (item.precioManual !== null) {
            precioUnitario = item.precioManual;
            precioOrigen = 'manual';
        } else if (precioUnitario === null && tarifaId === null) {
            avisos.push(`Falta el precio del ítem ${numero}.`);
        }

        let costoCompleto = true;
        const costeo = item.costeo.map((parte) => {
            let costoUnitario = parte.costoUnitario;
            let concepto = parte.concepto;
            let origen = 'manual';
            if (parte.costoId !== null && costoUnitario === null) {
                const costo = costos.get(parte.costoId);
                if (!costo) {
                    avisos.push(`Un costo del ítem ${numero} ya no existe.`);
                } else {
                    concepto = concepto || costo.concepto;
                    const valor = valorDeCosto(costo, mes, ipc);
                    valor.faltantes.forEach((m) => faltantes.add(m));
                    costoUnitario = valor.valor;
                    origen = 'tabla';
                    if (valor.valor === null) avisos.push(`El costo "${costo.concepto}" no tiene valor cargado (Precios > Costos): el margen del ítem ${numero} no se puede calcular.`);
                }
            }
            if (costoUnitario === null) costoCompleto = false;
            return { costoId: parte.costoId, concepto, cantidad: parte.cantidad, costoUnitario, origen };
        });

        return {
            orden: numero,
            tarifaId,
            tarifaNombre,
            descripcion: item.descripcion,
            alcance: item.alcance,
            cantidad: item.cantidad,
            precioUnitario,
            precioOrigen,
            precioTarifa,
            valorBase,
            mesBase,
            factor,
            periodicidad: item.periodicidad,
            prorratearMeses: item.prorratearMeses,
            bonificable: item.bonificable,
            costeo,
            costoCompleto,
            avisos,
        };
    });
    return { items: resueltos, faltantes: [...faltantes].sort() };
}

// Pasa los ítems resueltos (o los guardados) a lo que entiende la calculadora.
function paraCalculo(item) {
    const partes = Array.isArray(item.costeo) ? item.costeo : [];
    const completo = partes.every((p) => p.costoUnitario !== null && p.costoUnitario !== undefined);
    return {
        cantidad: item.cantidad,
        precioUnitario: item.precioUnitario ?? 0,
        periodicidad: item.periodicidad,
        prorratearMeses: item.prorratearMeses,
        bonificable: item.bonificable,
        // Si falta el valor de algún costo, el margen de ese ítem no se calcula (no se muestra uno falso).
        costeo: completo ? partes.map((p) => ({ cantidad: p.cantidad, costoUnitario: p.costoUnitario })) : [],
    };
}

function calcular(items, { bonificacion, iva, config }) {
    return calcularPresupuesto({
        items: items.map(paraCalculo),
        bonificacion,
        iva,
        margenMinimo: Number(config.margen_minimo),
        margenIdeal: Number(config.margen_ideal),
    });
}

// Lo que se le muestra al panel: porcentajes "de persona" (35 = 35 %).
function presentarCalculo(calculo, faltantes = []) {
    const avisos = calculo.avisos.map((a) => ({ tipo: a.tipo, linea: a.linea, mensaje: a.mensaje }));
    const avisoIPC = avisoIPCFaltante(faltantes);
    if (avisoIPC) avisos.unshift({ tipo: 'ipc_faltante', linea: null, mensaje: avisoIPC });
    return {
        lineas: calculo.lineas.map((l) => ({
            bruto: l.bruto, descuento: l.descuento, neto: l.neto, precioNetoUnitario: l.precioNetoUnitario, mensual: l.mensual, unico: l.unico,
            costo: l.costo, margen: porcentaje(l.margen), nivelMargen: l.nivelMargen,
        })),
        totalMensual: calculo.totalMensual,
        totalUnico: calculo.totalUnico,
        ivaMensual: calculo.ivaMensual,
        ivaUnico: calculo.ivaUnico,
        totalMensualConIva: calculo.totalMensualConIva,
        totalUnicoConIva: calculo.totalUnicoConIva,
        descuentoTotal: calculo.descuentoTotal,
        costoTotal: calculo.costoTotal,
        margen: porcentaje(calculo.margen),
        nivelMargen: calculo.nivelMargen,
        avisos,
    };
}

// --- Lectura de la base ---

function presentarItemGuardado(fila) {
    return {
        orden: fila.orden,
        tarifaId: fila.tarifa_id,
        descripcion: fila.descripcion,
        alcance: fila.alcance,
        cantidad: Number(fila.cantidad),
        precioUnitario: Number(fila.precio_unitario),
        precioOrigen: fila.precio_origen,
        valorBase: numeroONulo(fila.valor_base),
        mesBase: fila.mes_base,
        periodicidad: fila.periodicidad,
        prorratearMeses: fila.prorratear_meses,
        bonificable: fila.bonificable,
        costeo: (fila.costeo || []).map((p) => ({
            costoId: p.costoId ?? null, concepto: p.concepto || '', cantidad: Number(p.cantidad), costoUnitario: numeroONulo(p.costoUnitario), origen: p.origen || 'manual',
        })),
    };
}

function presentarEncabezado(fila) {
    return {
        id: fila.id,
        numero: fila.numero,
        version: fila.version,
        etiqueta: etiquetaDe(fila.numero, fila.version),
        empresaId: fila.empresa_id,
        cliente: fila.cliente,
        fecha: fila.fecha,
        mesReferencia: fila.mes_referencia,
        estado: fila.estado,
        bonificacion: porcentaje(Number(fila.bonificacion)),
        iva: porcentaje(Number(fila.iva)),
        formaPago: fila.forma_pago,
        plazoEntrega: fila.plazo_entrega,
        validez: fila.validez,
        referencia: fila.referencia,
        observaciones: fila.observaciones,
        fechaEnvio: fila.fecha_envio,
        prioridad: fila.prioridad || 'media',
        responsable: fila.responsable,
        fechaLimite: fila.fecha_limite,
        facturado: fila.facturado === true,
        notaSeguimiento: fila.nota_seguimiento,
        creadoPor: fila.creado_por,
        creadoEn: fila.creado_en,
        actualizadoEn: fila.actualizado_en,
    };
}

const COLUMNAS_PRESUPUESTO = `id, numero, version, empresa_id, cliente, to_char(fecha, 'YYYY-MM-DD') AS fecha, mes_referencia, estado,
    bonificacion, iva, forma_pago, plazo_entrega, validez, referencia, observaciones, to_char(fecha_envio, 'YYYY-MM-DD') AS fecha_envio,
    prioridad, responsable, to_char(fecha_limite, 'YYYY-MM-DD') AS fecha_limite, facturado, nota_seguimiento,
    creado_por, creado_en, actualizado_en`;

async function leerPresupuesto(consulta, id) {
    const cabecera = await consulta.query(`SELECT ${COLUMNAS_PRESUPUESTO} FROM presupuestos WHERE id = $1`, [id]);
    if (!cabecera.rows[0]) return null;
    const items = await consulta.query('SELECT * FROM presupuesto_items WHERE presupuesto_id = $1 ORDER BY orden', [id]);
    return { fila: cabecera.rows[0], items: items.rows.map(presentarItemGuardado) };
}

// Detalle completo: encabezado, ítems guardados, cuentas, versiones y notas de técnicos vinculadas.
async function detalleDePresupuesto(consulta, id) {
    const leido = await leerPresupuesto(consulta, id);
    if (!leido) return null;
    const config = await leerConfiguracion(consulta);
    const calculo = calcular(leido.items, { bonificacion: Number(leido.fila.bonificacion), iva: Number(leido.fila.iva), config });
    const [versiones, solicitudes] = await Promise.all([
        consulta.query(`SELECT id, version, estado, to_char(fecha, 'YYYY-MM-DD') AS fecha FROM presupuestos WHERE numero = $1 ORDER BY version`, [leido.fila.numero]),
        consulta.query('SELECT solicitud_id FROM presupuesto_solicitudes WHERE presupuesto_id = $1 ORDER BY solicitud_id', [id]),
    ]);
    const ultima = Math.max(...versiones.rows.map((v) => v.version));
    return {
        ...presentarEncabezado(leido.fila),
        editable: leido.fila.estado === 'Borrador',
        esUltimaVersion: leido.fila.version === ultima,
        items: leido.items,
        calculo: presentarCalculo(calculo),
        versiones: versiones.rows.map((v) => ({ id: v.id, version: v.version, etiqueta: etiquetaDe(leido.fila.numero, v.version), estado: v.estado, fecha: v.fecha })),
        solicitudIds: solicitudes.rows.map((s) => s.solicitud_id),
    };
}

async function guardarItems(cliente, presupuestoId, items) {
    for (const item of items) {
        await cliente.query(
            `INSERT INTO presupuesto_items
                (presupuesto_id, orden, tarifa_id, descripcion, alcance, cantidad, precio_unitario, precio_origen, valor_base, mes_base,
                 periodicidad, prorratear_meses, bonificable, costeo)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
            [
                presupuestoId, item.orden, item.tarifaId, item.descripcion, item.alcance, item.cantidad, item.precioUnitario, item.precioOrigen,
                item.valorBase, item.mesBase, item.periodicidad, item.prorratearMeses, item.bonificable,
                JSON.stringify(item.costeo.map((p) => ({ costoId: p.costoId, concepto: p.concepto, cantidad: p.cantidad, costoUnitario: p.costoUnitario, origen: p.origen }))),
            ]
        );
    }
}

// Todos los ítems tienen que tener precio para poder guardar el presupuesto.
function primerItemSinPrecio(items) {
    const indice = items.findIndex((i) => i.precioUnitario === null);
    return indice === -1 ? null : indice + 1;
}

function registrarRutasPresupuestos(app, { pool, soloComercial }) {
    // Cuentas en vivo mientras se arma el presupuesto (no guarda nada).
    app.post('/api/presupuestos/calcular', soloComercial, async (req, res) => {
        try {
            const config = await leerConfiguracion(pool);
            const limpio = limpiarEncabezado(req.body || {}, config);
            if (limpio.error) return res.status(400).json({ error: limpio.error });
            const d = limpio.datos;
            const [catalogos, ipc] = await Promise.all([cargarCatalogos(pool, d.items), leerIPC(pool)]);
            const { items, faltantes } = resolverItems(d.items, { mes: d.mesReferencia, ipc, config, ...catalogos });
            const calculo = calcular(items, { bonificacion: d.bonificacion, iva: Number(config.iva), config });
            res.json({ mesReferencia: d.mesReferencia, items, calculo: presentarCalculo(calculo, faltantes) });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo calcular el presupuesto' });
        }
    });

    app.get('/api/presupuestos', soloComercial, async (req, res) => {
        const condiciones = [];
        const valores = [];
        if (!vacio(req.query.estado)) {
            if (!ESTADOS.includes(req.query.estado)) return res.status(400).json({ error: 'Estado inválido' });
            valores.push(req.query.estado);
            condiciones.push(`p.estado = $${valores.length}`);
        }
        if (!vacio(req.query.empresaId)) {
            const empresaId = parseEntero(req.query.empresaId);
            if (Number.isNaN(empresaId)) return res.status(400).json({ error: 'Cliente inválido' });
            valores.push(empresaId);
            condiciones.push(`p.empresa_id = $${valores.length}`);
        }
        if (req.query.todas !== '1') condiciones.push('p.version = (SELECT MAX(version) FROM presupuestos WHERE numero = p.numero)');
        try {
            const donde = condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '';
            const filas = await pool.query(
                `SELECT p.id, p.numero, p.version, p.empresa_id, p.cliente, to_char(p.fecha, 'YYYY-MM-DD') AS fecha, p.estado, p.bonificacion, p.iva,
                        p.prioridad, p.responsable, to_char(p.fecha_limite, 'YYYY-MM-DD') AS fecha_limite, p.facturado, p.nota_seguimiento,
                        to_char(p.fecha_envio, 'YYYY-MM-DD') AS fecha_envio, p.creado_por, p.actualizado_en,
                        (SELECT COUNT(*)::int FROM presupuestos v WHERE v.numero = p.numero) AS cantidad_versiones
                 FROM presupuestos p ${donde} ORDER BY p.numero DESC, p.version DESC`,
                valores
            );
            const ids = filas.rows.map((f) => f.id);
            const itemsPorPresupuesto = new Map();
            if (ids.length) {
                const items = await pool.query('SELECT * FROM presupuesto_items WHERE presupuesto_id = ANY($1) ORDER BY presupuesto_id, orden', [ids]);
                for (const fila of items.rows) {
                    if (!itemsPorPresupuesto.has(fila.presupuesto_id)) itemsPorPresupuesto.set(fila.presupuesto_id, []);
                    itemsPorPresupuesto.get(fila.presupuesto_id).push(presentarItemGuardado(fila));
                }
            }
            const config = await leerConfiguracion(pool);
            res.json(filas.rows.map((fila) => {
                const items = itemsPorPresupuesto.get(fila.id) || [];
                const calculo = calcular(items, { bonificacion: Number(fila.bonificacion), iva: Number(fila.iva), config });
                return {
                    id: fila.id,
                    numero: fila.numero,
                    version: fila.version,
                    etiqueta: etiquetaDe(fila.numero, fila.version),
                    empresaId: fila.empresa_id,
                    cliente: (fila.cliente && fila.cliente.razonSocial) || 'Sin cliente',
                    fecha: fila.fecha,
                    estado: fila.estado,
                    bonificacion: porcentaje(Number(fila.bonificacion)),
                    cantidadItems: items.length,
                    cantidadVersiones: fila.cantidad_versiones,
                    totalMensual: calculo.totalMensual,
                    totalUnico: calculo.totalUnico,
                    nivelMargen: calculo.nivelMargen,
                    prioridad: fila.prioridad || 'media',
                    responsable: fila.responsable,
                    fechaLimite: fila.fecha_limite,
                    fechaEnvio: fila.fecha_envio,
                    facturado: fila.facturado === true,
                    notaSeguimiento: fila.nota_seguimiento,
                    creadoPor: fila.creado_por,
                    actualizadoEn: fila.actualizado_en,
                };
            }));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer la lista de presupuestos' });
        }
    });

    app.get('/api/presupuestos/:id', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Presupuesto inválido' });
        try {
            const detalle = await detalleDePresupuesto(pool, id);
            if (!detalle) return res.status(404).json({ error: 'Ese presupuesto no existe' });
            res.json(detalle);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo leer el presupuesto' });
        }
    });

    app.post('/api/presupuestos', soloComercial, async (req, res) => {
        const cliente = await pool.connect();
        try {
            const config = await leerConfiguracion(pool);
            const limpio = limpiarEncabezado(req.body || {}, config);
            if (limpio.error) return res.status(400).json({ error: limpio.error });
            const d = limpio.datos;
            if (!d.items.length) return res.status(400).json({ error: 'Agregá al menos un ítem al presupuesto' });

            await cliente.query('BEGIN');
            let empresa = null;
            if (d.empresaId !== null) {
                const encontrada = await cliente.query('SELECT * FROM empresas WHERE id = $1', [d.empresaId]);
                if (!encontrada.rows[0]) {
                    await cliente.query('ROLLBACK');
                    return res.status(400).json({ error: 'Ese cliente no existe' });
                }
                empresa = encontrada.rows[0];
            }
            const datosCliente = completarClienteConFicha(d.cliente, empresa);
            if (!datosCliente.razonSocial) {
                await cliente.query('ROLLBACK');
                return res.status(400).json({ error: 'Elegí el cliente o escribí su nombre' });
            }

            const [catalogos, ipc] = await Promise.all([cargarCatalogos(cliente, d.items), leerIPC(cliente)]);
            const { items } = resolverItems(d.items, { mes: d.mesReferencia, ipc, config, ...catalogos });
            const sinPrecio = primerItemSinPrecio(items);
            if (sinPrecio !== null) {
                await cliente.query('ROLLBACK');
                return res.status(400).json({ error: `Falta el precio del ítem ${sinPrecio}` });
            }

            // El número sale de un contador: se bloquea la fila para que dos personas no tomen el mismo.
            const contador = await cliente.query("SELECT valor FROM configuracion_comercial WHERE clave = 'proximo_numero' FOR UPDATE");
            const numero = contador.rows[0] ? Number(contador.rows[0].valor) : Number(config.proximo_numero);
            const quien = await quienEs(cliente, req);
            const nuevo = await cliente.query(
                `INSERT INTO presupuestos (numero, version, empresa_id, cliente, fecha, mes_referencia, bonificacion, iva,
                                           forma_pago, plazo_entrega, validez, referencia, observaciones, creado_por)
                 VALUES ($1, 1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) RETURNING id`,
                [
                    numero, d.empresaId, JSON.stringify(datosCliente), d.fecha, d.mesReferencia, d.bonificacion, Number(config.iva),
                    d.formaPago, d.plazoEntrega, d.validez, d.referencia, d.observaciones, quien,
                ]
            );
            const id = nuevo.rows[0].id;
            await guardarItems(cliente, id, items);
            await guardarClave(cliente, 'proximo_numero', numero + 1);
            await vincularSolicitudes(cliente, id, d.solicitudIds);
            await cliente.query('COMMIT');
            res.json(await detalleDePresupuesto(pool, id));
        } catch (error) {
            await cliente.query('ROLLBACK').catch(() => {});
            if (error.code === '23505') return res.status(409).json({ error: 'Ya existe un presupuesto con ese número. Cambiá el próximo número en Precios > Parámetros.' });
            if (error.mensaje) return res.status(error.estado || 400).json({ error: error.mensaje });
            console.error(error);
            res.status(500).json({ error: 'No se pudo crear el presupuesto' });
        } finally {
            cliente.release();
        }
    });

    // Cambia un borrador. Los presupuestos enviados no se tocan: se crea una versión nueva ("act").
    app.put('/api/presupuestos/:id', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Presupuesto inválido' });
        const cliente = await pool.connect();
        try {
            const config = await leerConfiguracion(pool);
            const limpio = limpiarEncabezado(req.body || {}, config);
            if (limpio.error) return res.status(400).json({ error: limpio.error });
            const d = limpio.datos;
            if (!d.items.length) return res.status(400).json({ error: 'Agregá al menos un ítem al presupuesto' });

            await cliente.query('BEGIN');
            const actual = await cliente.query('SELECT estado FROM presupuestos WHERE id = $1 FOR UPDATE', [id]);
            if (!actual.rows[0]) {
                await cliente.query('ROLLBACK');
                return res.status(404).json({ error: 'Ese presupuesto no existe' });
            }
            if (actual.rows[0].estado !== 'Borrador') {
                await cliente.query('ROLLBACK');
                return res.status(409).json({ error: 'Este presupuesto ya se envió y no se puede modificar. Creá una versión actualizada ("act").' });
            }
            let empresa = null;
            if (d.empresaId !== null) {
                const encontrada = await cliente.query('SELECT * FROM empresas WHERE id = $1', [d.empresaId]);
                if (!encontrada.rows[0]) {
                    await cliente.query('ROLLBACK');
                    return res.status(400).json({ error: 'Ese cliente no existe' });
                }
                empresa = encontrada.rows[0];
            }
            const datosCliente = completarClienteConFicha(d.cliente, empresa);
            if (!datosCliente.razonSocial) {
                await cliente.query('ROLLBACK');
                return res.status(400).json({ error: 'Elegí el cliente o escribí su nombre' });
            }
            const [catalogos, ipc] = await Promise.all([cargarCatalogos(cliente, d.items), leerIPC(cliente)]);
            const { items } = resolverItems(d.items, { mes: d.mesReferencia, ipc, config, ...catalogos });
            const sinPrecio = primerItemSinPrecio(items);
            if (sinPrecio !== null) {
                await cliente.query('ROLLBACK');
                return res.status(400).json({ error: `Falta el precio del ítem ${sinPrecio}` });
            }
            await cliente.query(
                `UPDATE presupuestos SET empresa_id = $1, cliente = $2, fecha = $3, mes_referencia = $4, bonificacion = $5, iva = $6,
                        forma_pago = $7, plazo_entrega = $8, validez = $9, referencia = $10, observaciones = $11, actualizado_en = now()
                 WHERE id = $12`,
                [d.empresaId, JSON.stringify(datosCliente), d.fecha, d.mesReferencia, d.bonificacion, Number(config.iva), d.formaPago, d.plazoEntrega, d.validez, d.referencia, d.observaciones, id]
            );
            await cliente.query('DELETE FROM presupuesto_items WHERE presupuesto_id = $1', [id]);
            await guardarItems(cliente, id, items);
            if (req.body.solicitudIds !== undefined) {
                await cliente.query('DELETE FROM presupuesto_solicitudes WHERE presupuesto_id = $1', [id]);
                await vincularSolicitudes(cliente, id, d.solicitudIds);
            }
            await cliente.query('COMMIT');
            res.json(await detalleDePresupuesto(pool, id));
        } catch (error) {
            await cliente.query('ROLLBACK').catch(() => {});
            if (error.mensaje) return res.status(error.estado || 400).json({ error: error.mensaje });
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar el presupuesto' });
        } finally {
            cliente.release();
        }
    });

    app.put('/api/presupuestos/:id/estado', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Presupuesto inválido' });
        const estado = req.body && req.body.estado;
        if (!ESTADOS.includes(estado)) return res.status(400).json({ error: 'Estado inválido' });
        const cliente = await pool.connect();
        try {
            await cliente.query('BEGIN');
            const actual = await cliente.query(`SELECT estado, numero, version FROM presupuestos WHERE id = $1 FOR UPDATE`, [id]);
            if (!actual.rows[0]) {
                await cliente.query('ROLLBACK');
                return res.status(404).json({ error: 'Ese presupuesto no existe' });
            }
            // El estado se maneja en la versión más nueva: las anteriores quedan como historial.
            const ultima = await cliente.query('SELECT MAX(version)::int AS version FROM presupuestos WHERE numero = $1', [actual.rows[0].numero]);
            if (actual.rows[0].version !== ultima.rows[0].version) {
                await cliente.query('ROLLBACK');
                return res.status(409).json({ error: 'Esta es una versión anterior: el estado se cambia en la versión más nueva.' });
            }
            // Un presupuesto solo vuelve a borrador si se había marcado como enviado por error; si ya avanzó, se hace una versión "act".
            if (estado === 'Borrador' && !['Borrador', 'Enviado'].includes(actual.rows[0].estado)) {
                await cliente.query('ROLLBACK');
                return res.status(409).json({ error: 'Este presupuesto ya avanzó y no puede volver a borrador. Para cambiarlo, creá una versión actualizada ("act").' });
            }
            if (estado !== 'Borrador') {
                const items = await cliente.query('SELECT COUNT(*)::int AS cantidad FROM presupuesto_items WHERE presupuesto_id = $1', [id]);
                if (!items.rows[0].cantidad) {
                    await cliente.query('ROLLBACK');
                    return res.status(400).json({ error: 'El presupuesto no tiene ítems' });
                }
            }
            // Al enviarlo se anota la fecha de envío (si no tenía) y las notas de técnicos pasan a "Presupuestada".
            await cliente.query(
                `UPDATE presupuestos SET estado = $1, fecha_envio = CASE WHEN $1 = 'Borrador' THEN NULL ELSE COALESCE(fecha_envio, $2::date) END, actualizado_en = now()
                 WHERE id = $3`,
                [estado, fechaDeHoy(), id]
            );
            if (estado !== 'Borrador') {
                await cliente.query(
                    `UPDATE solicitudes_presupuesto SET estado = 'Presupuestada', actualizada_en = now()
                     WHERE estado IN ('Nueva', 'En presupuesto') AND id IN (SELECT solicitud_id FROM presupuesto_solicitudes WHERE presupuesto_id = $1)`,
                    [id]
                );
            } else {
                // Si volvió a borrador, las notas que solo estaban en este presupuesto vuelven a "En presupuesto".
                await cliente.query(
                    `UPDATE solicitudes_presupuesto SET estado = 'En presupuesto', actualizada_en = now()
                     WHERE estado = 'Presupuestada'
                       AND id IN (SELECT solicitud_id FROM presupuesto_solicitudes WHERE presupuesto_id = $1)
                       AND id NOT IN (SELECT ps.solicitud_id FROM presupuesto_solicitudes ps
                                      JOIN presupuestos p ON p.id = ps.presupuesto_id
                                      WHERE ps.presupuesto_id <> $1 AND p.estado <> 'Borrador')`,
                    [id]
                );
            }
            await cliente.query('COMMIT');
            res.json(await detalleDePresupuesto(pool, id));
        } catch (error) {
            await cliente.query('ROLLBACK').catch(() => {});
            console.error(error);
            res.status(500).json({ error: 'No se pudo cambiar el estado' });
        } finally {
            cliente.release();
        }
    });

    // Datos del tablero (prioridad, quién lo sigue, fecha límite, facturado). No cambia el contenido del presupuesto.
    app.put('/api/presupuestos/:id/seguimiento', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Presupuesto inválido' });
        const cuerpo = req.body || {};
        if (cuerpo.prioridad !== undefined && !PRIORIDADES.includes(cuerpo.prioridad)) return res.status(400).json({ error: 'La prioridad no es válida' });
        const responsable = textoOpcional(cuerpo.responsable, 100, 'El responsable');
        if (responsable.error) return res.status(400).json({ error: responsable.error });
        const nota = textoOpcional(cuerpo.notaSeguimiento, 2000, 'La nota de seguimiento');
        if (nota.error) return res.status(400).json({ error: nota.error });
        let fechaLimite = undefined;
        if (cuerpo.fechaLimite !== undefined) {
            if (vacio(cuerpo.fechaLimite)) fechaLimite = null;
            else if (!fechaValida(String(cuerpo.fechaLimite).trim())) return res.status(400).json({ error: 'La fecha límite no es válida' });
            else fechaLimite = String(cuerpo.fechaLimite).trim();
        }
        const cliente = await pool.connect();
        try {
            await cliente.query('BEGIN');
            const actual = await cliente.query('SELECT numero, version FROM presupuestos WHERE id = $1 FOR UPDATE', [id]);
            if (!actual.rows[0]) {
                await cliente.query('ROLLBACK');
                return res.status(404).json({ error: 'Ese presupuesto no existe' });
            }
            const ultima = await cliente.query('SELECT MAX(version)::int AS version FROM presupuestos WHERE numero = $1', [actual.rows[0].numero]);
            if (actual.rows[0].version !== ultima.rows[0].version) {
                await cliente.query('ROLLBACK');
                return res.status(409).json({ error: 'Esta es una versión anterior: el seguimiento se carga en la versión más nueva.' });
            }
            const sets = [];
            const valores = [];
            const poner = (sql, valor) => { valores.push(valor); sets.push(`${sql} = $${valores.length}`); };
            if (cuerpo.prioridad !== undefined) poner('prioridad', cuerpo.prioridad);
            if (cuerpo.responsable !== undefined) poner('responsable', responsable.texto);
            if (fechaLimite !== undefined) poner('fecha_limite', fechaLimite);
            if (cuerpo.facturado !== undefined) poner('facturado', booleano(cuerpo.facturado, false));
            if (cuerpo.notaSeguimiento !== undefined) poner('nota_seguimiento', nota.texto);
            if (!sets.length) {
                await cliente.query('ROLLBACK');
                return res.status(400).json({ error: 'No hay nada para cambiar' });
            }
            valores.push(id);
            await cliente.query(`UPDATE presupuestos SET ${sets.join(', ')}, actualizado_en = now() WHERE id = $${valores.length}`, valores);
            await cliente.query('COMMIT');
            res.json(await detalleDePresupuesto(pool, id));
        } catch (error) {
            await cliente.query('ROLLBACK').catch(() => {});
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar el seguimiento' });
        } finally {
            cliente.release();
        }
    });

    // Nueva versión ("act"): mismo número, fecha de hoy y, si se pide, precios actualizados por inflación.
    app.post('/api/presupuestos/:id/actualizar', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Presupuesto inválido' });
        const repreciar = booleano(req.body && req.body.repreciar, true);
        const cliente = await pool.connect();
        try {
            await cliente.query('BEGIN');
            const origen = await leerPresupuesto(cliente, id);
            if (!origen) {
                await cliente.query('ROLLBACK');
                return res.status(404).json({ error: 'Ese presupuesto no existe' });
            }
            // Se bloquean las versiones de ese número para que no se creen dos "act" a la vez.
            await cliente.query('SELECT id FROM presupuestos WHERE numero = $1 FOR UPDATE', [origen.fila.numero]);
            const ultima = await cliente.query('SELECT MAX(version)::int AS version FROM presupuestos WHERE numero = $1', [origen.fila.numero]);
            if (origen.fila.version !== ultima.rows[0].version) {
                await cliente.query('ROLLBACK');
                return res.status(409).json({ error: 'Ya hay una versión más nueva de este presupuesto. Abrí esa para actualizarla.' });
            }
            const config = await leerConfiguracion(cliente);
            const hoy = fechaDeHoy();
            const mes = aMes(hoy);
            let items = origen.items;
            if (repreciar) {
                const pedidos = origen.items.map((item) => ({
                    tarifaId: item.tarifaId,
                    descripcion: item.descripcion,
                    alcance: item.alcance,
                    cantidad: item.cantidad,
                    // Lo que se escribió a mano se respeta; lo que venía del tarifario se vuelve a calcular.
                    precioManual: item.precioOrigen === 'manual' ? item.precioUnitario : null,
                    periodicidad: item.periodicidad,
                    prorratearMeses: item.prorratearMeses,
                    bonificable: item.bonificable,
                    costeo: item.costeo.map((p) => ({ costoId: p.costoId, concepto: p.concepto, cantidad: p.cantidad, costoUnitario: p.origen === 'manual' ? p.costoUnitario : null })),
                }));
                const [catalogos, ipc] = await Promise.all([cargarCatalogos(cliente, pedidos), leerIPC(cliente)]);
                items = resolverItems(pedidos, { mes, ipc, config, ...catalogos }).items;
                const sinPrecio = primerItemSinPrecio(items);
                if (sinPrecio !== null) {
                    await cliente.query('ROLLBACK');
                    return res.status(409).json({ error: `El ítem ${sinPrecio} ya no tiene precio en el tarifario: ponele el precio a mano en el presupuesto original o completá el tarifario.` });
                }
            }
            const f = origen.fila;
            const quien = await quienEs(cliente, req);
            const nuevo = await cliente.query(
                `INSERT INTO presupuestos (numero, version, empresa_id, cliente, fecha, mes_referencia, bonificacion, iva,
                                           forma_pago, plazo_entrega, validez, referencia, observaciones, creado_por,
                                           prioridad, responsable, fecha_limite, nota_seguimiento)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18) RETURNING id`,
                [f.numero, f.version + 1, f.empresa_id, JSON.stringify(f.cliente), hoy, mes, f.bonificacion, f.iva, f.forma_pago, f.plazo_entrega, f.validez, f.referencia, f.observaciones, quien,
                    f.prioridad || 'media', f.responsable, f.fecha_limite, f.nota_seguimiento]
            );
            const nuevoId = nuevo.rows[0].id;
            await guardarItems(cliente, nuevoId, items.map((item, i) => ({
                ...item,
                orden: i + 1,
                // Si no se actualizaron los precios, se copian tal cual estaban.
                precioOrigen: item.precioOrigen,
                valorBase: item.valorBase ?? null,
                mesBase: item.mesBase ?? null,
            })));
            await cliente.query(
                'INSERT INTO presupuesto_solicitudes (presupuesto_id, solicitud_id) SELECT $1, solicitud_id FROM presupuesto_solicitudes WHERE presupuesto_id = $2',
                [nuevoId, id]
            );
            await cliente.query('COMMIT');
            res.json(await detalleDePresupuesto(pool, nuevoId));
        } catch (error) {
            await cliente.query('ROLLBACK').catch(() => {});
            console.error(error);
            res.status(500).json({ error: 'No se pudo crear la versión actualizada' });
        } finally {
            cliente.release();
        }
    });

    app.delete('/api/presupuestos/:id', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Presupuesto inválido' });
        const cliente = await pool.connect();
        try {
            await cliente.query('BEGIN');
            const actual = await cliente.query('SELECT estado FROM presupuestos WHERE id = $1 FOR UPDATE', [id]);
            if (!actual.rows[0]) {
                await cliente.query('ROLLBACK');
                return res.status(404).json({ error: 'Ese presupuesto no existe' });
            }
            if (actual.rows[0].estado !== 'Borrador') {
                await cliente.query('ROLLBACK');
                return res.status(409).json({ error: 'Solo se pueden borrar los borradores. Un presupuesto enviado queda como historial: marcalo como Rechazado.' });
            }
            // Las notas que solo estaban en este borrador vuelven a "Nueva".
            await cliente.query(
                `UPDATE solicitudes_presupuesto SET estado = 'Nueva', actualizada_en = now()
                 WHERE estado = 'En presupuesto'
                   AND id IN (SELECT solicitud_id FROM presupuesto_solicitudes WHERE presupuesto_id = $1)
                   AND id NOT IN (SELECT solicitud_id FROM presupuesto_solicitudes WHERE presupuesto_id <> $1)`,
                [id]
            );
            await cliente.query('DELETE FROM presupuestos WHERE id = $1', [id]);
            await cliente.query('COMMIT');
            res.json({ ok: true });
        } catch (error) {
            await cliente.query('ROLLBACK').catch(() => {});
            console.error(error);
            res.status(500).json({ error: 'No se pudo borrar el presupuesto' });
        } finally {
            cliente.release();
        }
    });

    app.get('/api/presupuestos/:id/pdf', soloComercial, async (req, res) => {
        const id = parseEntero(req.params.id);
        if (Number.isNaN(id)) return res.status(400).json({ error: 'Presupuesto inválido' });
        try {
            const leido = await leerPresupuesto(pool, id);
            if (!leido) return res.status(404).json({ error: 'Ese presupuesto no existe' });
            const config = await leerConfiguracion(pool);
            const calculo = calcular(leido.items, { bonificacion: Number(leido.fila.bonificacion), iva: Number(leido.fila.iva), config });
            const nombreArchivo = `Presupuesto ${etiquetaDe(leido.fila.numero, leido.fila.version)} - ${(leido.fila.cliente && leido.fila.cliente.razonSocial) || 'cliente'}`
                .normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^\w .()-]/g, '').replace(/\s+/g, ' ').trim();
            res.setHeader('Content-Type', 'application/pdf');
            res.setHeader('Content-Disposition', `inline; filename="${nombreArchivo}.pdf"`);
            res.setHeader('Cache-Control', 'no-store');
            await crearPresupuestoPdf(res, {
                config,
                etiqueta: etiquetaDe(leido.fila.numero, leido.fila.version),
                fecha: leido.fila.fecha,
                cliente: leido.fila.cliente || {},
                formaPago: leido.fila.forma_pago,
                plazoEntrega: leido.fila.plazo_entrega,
                validez: leido.fila.validez,
                referencia: leido.fila.referencia,
                observaciones: leido.fila.observaciones,
                items: leido.items,
                calculo,
                mesReferencia: nombreDelMes(leido.fila.mes_referencia),
            });
        } catch (error) {
            console.error(error);
            if (!res.headersSent) res.status(500).json({ error: 'No se pudo generar el PDF' });
            else res.end();
        }
    });
}

// Quién está haciendo el pedido (nombre de su cuenta; si no se encuentra, su correo).
async function quienEs(consulta, req) {
    const id = req.usuario ? Number(req.usuario.id) : NaN;
    if (Number.isInteger(id)) {
        const cuenta = await consulta.query('SELECT nombre FROM admins WHERE id = $1', [id]);
        if (cuenta.rows[0]) return cuenta.rows[0].nombre;
    }
    return req.usuario && req.usuario.email ? String(req.usuario.email) : null;
}

// Marca las notas de técnicos como "En presupuesto" y las vincula al presupuesto.
async function vincularSolicitudes(cliente, presupuestoId, solicitudIds) {
    if (!solicitudIds.length) return;
    const existentes = await cliente.query('SELECT id FROM solicitudes_presupuesto WHERE id = ANY($1)', [solicitudIds]);
    if (existentes.rows.length !== solicitudIds.length) {
        const error = new Error('Alguna de las notas de técnicos ya no existe');
        error.mensaje = 'Alguna de las notas de técnicos ya no existe';
        error.estado = 400;
        throw error;
    }
    for (const solicitudId of solicitudIds) {
        await cliente.query('INSERT INTO presupuesto_solicitudes (presupuesto_id, solicitud_id) VALUES ($1, $2) ON CONFLICT DO NOTHING', [presupuestoId, solicitudId]);
    }
    await cliente.query(
        `UPDATE solicitudes_presupuesto SET estado = 'En presupuesto', actualizada_en = now() WHERE estado = 'Nueva' AND id = ANY($1)`,
        [solicitudIds]
    );
}

module.exports = { ESTADOS, PRIORIDADES, etiquetaDe, registrarRutasPresupuestos, resolverItems, calcular, limpiarEncabezado };
