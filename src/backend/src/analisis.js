// Análisis del panel: períodos, checklist, tiempos y encuestas.
// Solo usa lo que ya queda guardado de las visitas. No inventa plata ni métricas que no existen.
const { fechaDeHoy } = require('./indexacion');

const PERIODOS = ['hoy', '7d', 'mes', 'trimestre', 'custom'];
const MAX_DIAS = 366 * 5;

function iso(anio, mes, dia) {
    return `${anio}-${String(mes).padStart(2, '0')}-${String(dia).padStart(2, '0')}`;
}

function partes(fecha) {
    const [anio, mes, dia] = fecha.split('-').map(Number);
    return { anio, mes, dia };
}

function fechaReal(valor) {
    const texto = String(valor || '').slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(texto)) return null;
    const { anio, mes, dia } = partes(texto);
    const fecha = new Date(Date.UTC(anio, mes - 1, dia));
    if (fecha.getUTCFullYear() !== anio || fecha.getUTCMonth() !== mes - 1 || fecha.getUTCDate() !== dia) return null;
    return texto;
}

function sumarDias(fecha, dias) {
    const { anio, mes, dia } = partes(fecha);
    const valor = new Date(Date.UTC(anio, mes - 1, dia));
    valor.setUTCDate(valor.getUTCDate() + dias);
    return iso(valor.getUTCFullYear(), valor.getUTCMonth() + 1, valor.getUTCDate());
}

function finDeMes(anio, mes) {
    return new Date(Date.UTC(anio, mes, 0)).getUTCDate();
}

function diasEntre(desde, hasta) {
    const a = partes(desde);
    const b = partes(hasta);
    const inicio = Date.UTC(a.anio, a.mes - 1, a.dia);
    const fin = Date.UTC(b.anio, b.mes - 1, b.dia);
    return Math.round((fin - inicio) / 86400000) + 1;
}

function rangoDe(periodo, hoy, desde, hasta) {
    const { anio, mes } = partes(hoy);
    if (periodo === 'hoy') return { desde: hoy, hasta: hoy };
    if (periodo === '7d') return { desde: sumarDias(hoy, -6), hasta: hoy };
    if (periodo === 'mes') return { desde: iso(anio, mes, 1), hasta: iso(anio, mes, finDeMes(anio, mes)) };
    if (periodo === 'trimestre') {
        const inicioMes = mes - ((mes - 1) % 3);
        const finMes = inicioMes + 2;
        return { desde: iso(anio, inicioMes, 1), hasta: iso(anio, finMes, finDeMes(anio, finMes)) };
    }
    const desdeOk = fechaReal(desde);
    const hastaOk = fechaReal(hasta);
    if (!desdeOk || !hastaOk || desdeOk > hastaOk) return null;
    if (diasEntre(desdeOk, hastaOk) > MAX_DIAS) return { error: 'El período es demasiado largo' };
    return { desde: desdeOk, hasta: hastaOk };
}

function rangoAnterior(desde, hasta, periodo) {
    if (periodo === 'mes' || periodo === 'trimestre') {
        const { anio, mes } = partes(desde);
        const salto = periodo === 'mes' ? 1 : 3;
        let mesInicio = mes - salto;
        let anioInicio = anio;
        while (mesInicio <= 0) {
            mesInicio += 12;
            anioInicio -= 1;
        }
        const meses = periodo === 'mes' ? 1 : 3;
        let mesFin = mesInicio + meses - 1;
        let anioFin = anioInicio;
        if (mesFin > 12) {
            mesFin -= 12;
            anioFin += 1;
        }
        return { desde: iso(anioInicio, mesInicio, 1), hasta: iso(anioFin, mesFin, finDeMes(anioFin, mesFin)) };
    }
    const cantidad = diasEntre(desde, hasta);
    const hastaPrevio = sumarDias(desde, -1);
    return { desde: sumarDias(hastaPrevio, -(cantidad - 1)), hasta: hastaPrevio };
}

function comparacionDe(periodo) {
    if (periodo === 'hoy') return 'vs día anterior';
    if (periodo === '7d') return 'vs 7 días anteriores';
    if (periodo === 'mes') return 'vs mes anterior';
    if (periodo === 'trimestre') return 'vs trimestre anterior';
    return 'vs período anterior';
}

function leerId(valor) {
    if (valor == null || valor === '') return null;
    if (Array.isArray(valor) || !/^\d{1,9}$/.test(String(valor))) return NaN;
    const numero = Number(valor);
    return numero > 0 ? numero : NaN;
}

function interpretarFiltros(query, ahora = new Date()) {
    const pedido = query || {};
    const periodo = pedido.periodo || 'mes';
    if (!PERIODOS.includes(periodo)) return { error: 'Período inválido', status: 400 };
    const hoy = fechaDeHoy(ahora);
    const rango = rangoDe(periodo, hoy, pedido.desde, pedido.hasta);
    if (!rango) return { error: 'Elegí un rango de fechas válido', status: 400 };
    if (rango.error) return { error: rango.error, status: 400 };
    const empresaId = leerId(pedido.empresaId);
    const tecnicoId = leerId(pedido.tecnicoId);
    if (Number.isNaN(empresaId) || Number.isNaN(tecnicoId)) return { error: 'Filtro inválido', status: 400 };
    const anterior = rangoAnterior(rango.desde, rango.hasta, periodo);
    return {
        periodo,
        hoy,
        desde: rango.desde,
        hasta: rango.hasta,
        anteriorDesde: anterior.desde,
        anteriorHasta: anterior.hasta,
        comparacion: comparacionDe(periodo),
        empresaId,
        tecnicoId,
    };
}

function normalizarChecklist(valor) {
    if (!Array.isArray(valor)) return null;
    return valor.map((item) => {
        if (!item || typeof item !== 'object') return null;
        const tarea = String(item.tarea || '').trim().slice(0, 200);
        if (!tarea) return null;
        const hecho = item.hecho === true || item.hecho === 'true' || item.hecho === 1 || item.hecho === '1';
        return { tarea, hecho };
    }).filter(Boolean).slice(0, 80);
}

function listaChecklist(valor) {
    if (typeof valor === 'string') {
        try {
            return normalizarChecklist(JSON.parse(valor)) || [];
        } catch {
            return [];
        }
    }
    return normalizarChecklist(valor) || [];
}

function numero(valor) {
    if (valor == null || valor === '') return null;
    const n = Number(valor);
    return Number.isFinite(n) ? n : null;
}

function cumplimiento(listas) {
    let hechos = 0;
    let total = 0;
    for (const items of listas) {
        for (const item of items || []) {
            if (!item || !String(item.tarea || '').trim()) continue;
            total += 1;
            if (item.hecho) hechos += 1;
        }
    }
    return { hechos, total, porcentaje: total ? Math.round((hechos * 100) / total) : null };
}

function topFallas(listas, limite = 5) {
    const mapa = new Map();
    for (const items of listas) {
        for (const item of items || []) {
            const tarea = String(item && item.tarea || '').trim();
            if (!tarea) continue;
            const clave = tarea.toLocaleLowerCase('es');
            const actual = mapa.get(clave) || { tarea, fallos: 0, total: 0 };
            actual.total += 1;
            if (!item.hecho) actual.fallos += 1;
            mapa.set(clave, actual);
        }
    }
    return [...mapa.values()]
        .filter((fila) => fila.fallos > 0)
        .sort((a, b) => b.fallos - a.fallos || b.total - a.total || a.tarea.localeCompare(b.tarea, 'es'))
        .slice(0, limite);
}

function variacion(actual, anterior) {
    const ahora = Number(actual) || 0;
    const antes = Number(anterior) || 0;
    if (!antes) return ahora ? null : 0;
    return Math.round(((ahora - antes) * 100) / antes);
}

function fechaHoraArgentina(valor) {
    if (!valor) return '';
    const fecha = new Date(valor);
    if (Number.isNaN(fecha.getTime())) return '';
    return new Intl.DateTimeFormat('es-AR', {
        timeZone: 'America/Argentina/Buenos_Aires',
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
    }).format(fecha);
}

const MESES_CORTOS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

function lunesDe(fecha) {
    const { anio, mes, dia } = partes(fecha);
    const valor = new Date(Date.UTC(anio, mes - 1, dia));
    valor.setUTCDate(valor.getUTCDate() - ((valor.getUTCDay() + 6) % 7));
    return iso(valor.getUTCFullYear(), valor.getUTCMonth() + 1, valor.getUTCDate());
}

function etiquetaMes(anio, mes, conAnio) {
    const nombre = MESES_CORTOS[mes - 1];
    return conAnio ? `${nombre} ${String(anio).slice(2)}` : nombre;
}

// Barras del período: por semana si entra en un mes y medio, si no por mes.
function serieDe(filas, desde, hasta) {
    const porSemana = diasEntre(desde, hasta) <= 45;
    const mapa = new Map();
    const conAnio = desde.slice(0, 4) !== hasta.slice(0, 4);
    if (porSemana) {
        let cursor = lunesDe(desde);
        while (cursor <= hasta && mapa.size < 12) {
            const fecha = partes(cursor);
            mapa.set(cursor, {
                etiqueta: `${String(fecha.dia).padStart(2, '0')}/${String(fecha.mes).padStart(2, '0')}`,
                ordenes: 0,
                completadas: 0,
            });
            cursor = sumarDias(cursor, 7);
        }
    } else {
        let { anio, mes } = partes(desde);
        const fin = partes(hasta);
        while (mapa.size < 18 && (anio < fin.anio || (anio === fin.anio && mes <= fin.mes))) {
            mapa.set(`${anio}-${String(mes).padStart(2, '0')}`, {
                etiqueta: etiquetaMes(anio, mes, conAnio),
                ordenes: 0,
                completadas: 0,
            });
            mes += 1;
            if (mes === 13) {
                mes = 1;
                anio += 1;
            }
        }
    }
    for (const fila of filas) {
        if (!fila.fecha) continue;
        const clave = porSemana ? lunesDe(fila.fecha) : String(fila.fecha).slice(0, 7);
        const bucket = mapa.get(clave);
        if (!bucket) continue;
        bucket.ordenes += 1;
        if (fila.estado === 'Completada') bucket.completadas += 1;
    }
    return { modo: porSemana ? 'semana' : 'mes', puntos: [...mapa.values()] };
}

function porClienteDe(filas) {
    const mapa = new Map();
    for (const fila of filas) {
        const nombre = fila.cliente || 'Sin cliente';
        const actual = mapa.get(nombre) || { nombre, ordenes: 0, completadas: 0 };
        actual.ordenes += 1;
        if (fila.estado === 'Completada') actual.completadas += 1;
        mapa.set(nombre, actual);
    }
    return [...mapa.values()]
        .sort((a, b) => b.ordenes - a.ordenes || a.nombre.localeCompare(b.nombre, 'es'))
        .slice(0, 8);
}

function promedio(valores) {
    if (!valores.length) return null;
    const suma = valores.reduce((total, valor) => total + valor, 0);
    return Math.round((suma / valores.length) * 10) / 10;
}

function armarVista({ ordenes, ordenesAnteriores, encuestas, clientes, tecnicos, filtros }) {
    const filas = Array.isArray(ordenes) ? ordenes : [];
    const abiertas = filas.filter((fila) => fila.estado !== 'Completada');
    const completadas = filas.filter((fila) => fila.estado === 'Completada');
    const vencidas = abiertas.filter((fila) => fila.fecha && fila.fecha < filtros.hoy);
    const listas = completadas.map((fila) => listaChecklist(fila.checklist_cierre));
    const checklist = cumplimiento(listas);
    const minutos = completadas.map((fila) => numero(fila.minutos)).filter((valor) => valor != null && valor > 0);
    const minutosTotal = minutos.reduce((total, valor) => total + valor, 0);
    const comentarios = completadas
        .map((fila) => ({
            ordenId: Number(fila.id),
            cliente: fila.cliente || 'Sin cliente',
            fecha: fila.fecha || '',
            tecnico: fila.tecnico || 'Sin técnico',
            texto: String(fila.comentarios_cierre || '').trim(),
            solicitudId: fila.solicitud_id == null ? null : Number(fila.solicitud_id),
            empresaId: fila.empresa_id == null ? null : Number(fila.empresa_id),
        }))
        .filter((fila) => fila.texto)
        .sort((a, b) => b.fecha.localeCompare(a.fecha) || b.ordenId - a.ordenId);

    const porTecnico = new Map();
    for (const fila of filas) {
        const id = fila.tecnico_id == null ? 0 : Number(fila.tecnico_id);
        const actual = porTecnico.get(id) || {
            id,
            nombre: fila.tecnico || 'Sin técnico',
            asignadas: 0,
            completadas: 0,
            minutos: 0,
            visitas: 0,
            hechos: 0,
            tareas: 0,
            notas: [],
        };
        actual.asignadas += 1;
        if (fila.estado === 'Completada') {
            actual.completadas += 1;
            const duracion = numero(fila.minutos);
            if (duracion != null && duracion > 0) {
                actual.minutos += duracion;
                actual.visitas += 1;
            }
            const items = listaChecklist(fila.checklist_cierre);
            for (const item of items) {
                actual.tareas += 1;
                if (item.hecho) actual.hechos += 1;
            }
        }
        porTecnico.set(id, actual);
    }

    const respuestas = (Array.isArray(encuestas) ? encuestas : [])
        .map((fila) => ({
            puntaje: numero(fila.puntaje),
            comentario: String(fila.comentario || '').trim(),
            cliente: fila.cliente || 'Sin cliente',
            tecnico: fila.tecnico || 'Sin técnico',
            tecnicoId: fila.tecnico_id == null ? 0 : Number(fila.tecnico_id),
            cuando: fechaHoraArgentina(fila.respondida_en || fila.enviada_en),
            respondida: numero(fila.puntaje) != null,
        }))
        .sort((a, b) => b.cuando.localeCompare(a.cuando));

    for (const respuesta of respuestas) {
        if (respuesta.puntaje == null) continue;
        const tecnico = porTecnico.get(respuesta.tecnicoId);
        if (tecnico) tecnico.notas.push(respuesta.puntaje);
    }

    const equipo = [...porTecnico.values()]
        .map((fila) => ({
            id: fila.id,
            nombre: fila.nombre,
            asignadas: fila.asignadas,
            completadas: fila.completadas,
            checklist: fila.tareas ? Math.round((fila.hechos * 100) / fila.tareas) : null,
            promedioMinutos: fila.visitas ? Math.round(fila.minutos / fila.visitas) : null,
            minutos: fila.minutos,
            visitas: fila.visitas,
            calificacion: promedio(fila.notas),
            respuestas: fila.notas.length,
        }))
        .sort((a, b) => b.completadas - a.completadas || a.nombre.localeCompare(b.nombre, 'es'));

    const conNota = respuestas.filter((fila) => fila.puntaje != null);
    const distribucion = [0, 0, 0, 0, 0];
    for (const fila of conNota) {
        const nota = Math.round(fila.puntaje);
        if (nota >= 1 && nota <= 5) distribucion[nota - 1] += 1;
    }
    const enviados = respuestas.length;
    const respondidas = conNota.length;

    return {
        periodo: filtros.periodo,
        desde: filtros.desde,
        hasta: filtros.hasta,
        comparacion: filtros.comparacion,
        opciones: {
            clientes: (clientes || []).map((fila) => ({ id: Number(fila.id), nombre: fila.nombre })),
            tecnicos: (tecnicos || []).map((fila) => ({ id: Number(fila.id), nombre: fila.nombre })),
        },
        kpis: {
            ordenes: filas.length,
            variacion: variacion(filas.length, ordenesAnteriores),
            pendientes: abiertas.length,
            vencidas: vencidas.length,
            checklist: checklist.porcentaje,
            checklistHechos: checklist.hechos,
            checklistTotal: checklist.total,
            completadas: completadas.length,
            tasaCierre: filas.length ? Math.round((completadas.length * 100) / filas.length) : null,
            promedioMinutos: minutos.length ? Math.round(minutosTotal / minutos.length) : null,
        },
        serie: serieDe(filas, filtros.desde, filtros.hasta),
        porCliente: porClienteDe(filas),
        fallas: topFallas(listas),
        comentarios,
        tecnicos: equipo,
        encuestas: {
            enviados,
            respondidas,
            tasa: enviados ? Math.round((respondidas * 100) / enviados) : null,
            promedio: promedio(conNota.map((fila) => fila.puntaje)),
            respuestas: respondidas,
            distribucion,
            detalle: conNota.map(({ puntaje, comentario, cliente, tecnico, cuando }) => ({
                puntaje, comentario, cliente, tecnico, cuando,
            })),
        },
        totales: {
            ordenes: filas.length,
            completadas: completadas.length,
            pendientes: filas.filter((fila) => fila.estado === 'Pendiente').length,
            en_progreso: filas.filter((fila) => fila.estado === 'En progreso').length,
            por_asignar: filas.filter((fila) => fila.estado === 'Por asignar').length,
        },
        tiempos: equipo.filter((fila) => fila.visitas > 0).map((fila) => ({
            nombre: fila.nombre,
            visitas: fila.visitas,
            promedio_minutos: fila.promedioMinutos || 0,
            minutos: fila.minutos,
        })),
    };
}

const FILTRO_ORDEN = `
    o.fecha_asignada BETWEEN $1::date AND $2::date
    AND ($3::int IS NULL OR o.empresa_id = $3::int)
    AND ($4::int IS NULL OR o.tecnico_id = $4::int)
`;

const SQL_ORDENES = `
    SELECT o.id, o.estado, to_char(o.fecha_asignada, 'YYYY-MM-DD') AS fecha,
           o.comentarios_cierre, o.checklist_cierre, o.tecnico_id,
           COALESCE(t.nombre, 'Sin técnico') AS tecnico,
           o.empresa_id, COALESCE(e.razon_social, 'Sin cliente') AS cliente,
           v.minutos, s.id AS solicitud_id
    FROM ordenes o
    LEFT JOIN tecnicos t ON t.id = o.tecnico_id
    LEFT JOIN empresas e ON e.id = o.empresa_id
    LEFT JOIN visitas v ON v.orden_id = o.id
    LEFT JOIN solicitudes_presupuesto s ON s.id_cliente = ('cierre-orden-' || o.id::text)
    WHERE ${FILTRO_ORDEN}
`;

const SQL_CONTEO = `SELECT COUNT(*)::int AS ordenes FROM ordenes o WHERE ${FILTRO_ORDEN}`;

const SQL_ENCUESTAS = `
    SELECT e.puntaje, e.comentario, e.cliente, e.respondida_en, e.enviada_en,
           t.nombre AS tecnico, o.tecnico_id
    FROM encuestas e
    LEFT JOIN ordenes o ON o.id = e.orden_id
    LEFT JOIN tecnicos t ON t.id = o.tecnico_id
    WHERE e.enviada_en IS NOT NULL
      AND (e.enviada_en AT TIME ZONE 'America/Argentina/Buenos_Aires')::date BETWEEN $1::date AND $2::date
      AND ($3::int IS NULL OR o.empresa_id = $3::int)
      AND ($4::int IS NULL OR o.tecnico_id = $4::int)
`;

const SQL_CLIENTES = `
    SELECT e.id, e.razon_social AS nombre
    FROM empresas e
    WHERE EXISTS (SELECT 1 FROM ordenes o WHERE o.empresa_id = e.id)
    ORDER BY e.razon_social
`;

const SQL_TECNICOS = 'SELECT id, nombre FROM tecnicos ORDER BY nombre';

async function consultarAnalisis(pool, query, ahora = new Date()) {
    const filtros = interpretarFiltros(query, ahora);
    if (filtros.error) return filtros;
    const params = [filtros.desde, filtros.hasta, filtros.empresaId, filtros.tecnicoId];
    const anteriores = [filtros.anteriorDesde, filtros.anteriorHasta, filtros.empresaId, filtros.tecnicoId];
    const [ordenes, conteo, encuestas, clientes, tecnicos] = await Promise.all([
        pool.query(SQL_ORDENES, params),
        pool.query(SQL_CONTEO, anteriores),
        pool.query(SQL_ENCUESTAS, params),
        pool.query(SQL_CLIENTES),
        pool.query(SQL_TECNICOS),
    ]);
    return armarVista({
        ordenes: ordenes.rows,
        ordenesAnteriores: conteo.rows[0] ? conteo.rows[0].ordenes : 0,
        encuestas: encuestas.rows,
        clientes: clientes.rows,
        tecnicos: tecnicos.rows,
        filtros,
    });
}

async function crearPresupuestoDesdeComentario(pool, ordenId) {
    if (!Number.isInteger(ordenId) || ordenId <= 0) return { error: 'Orden inválida', status: 400 };
    const orden = await pool.query(
        `SELECT o.id, o.comentarios_cierre, o.empresa_id, o.tecnico_id,
                COALESCE(e.razon_social, 'Sin cliente') AS empresa, t.nombre AS tecnico
         FROM ordenes o
         LEFT JOIN empresas e ON e.id = o.empresa_id
         LEFT JOIN tecnicos t ON t.id = o.tecnico_id
         WHERE o.id = $1`,
        [ordenId]
    );
    const fila = orden.rows[0];
    if (!fila) return { error: 'Esa orden no existe', status: 404 };
    const texto = String(fila.comentarios_cierre || '').trim().slice(0, 500);
    if (!texto) return { error: 'Esa visita no tiene un comentario para presupuestar', status: 400 };
    const idCliente = `cierre-orden-${ordenId}`;
    await pool.query(
        `INSERT INTO solicitudes_presupuesto
            (id_cliente, empresa_id, empresa_nombre, orden_id, tecnico_id, tecnico_nombre, descripcion, cantidad)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 1)
         ON CONFLICT (id_cliente) DO NOTHING`,
        [idCliente, fila.empresa_id, fila.empresa, fila.id, fila.tecnico_id, fila.tecnico, texto]
    );
    const nota = await pool.query(
        `SELECT s.id, s.empresa_id, s.descripcion, s.cantidad, s.estado, s.orden_id,
                COALESCE(e.razon_social, s.empresa_nombre, 'Sin cliente') AS empresa,
                COALESCE(t.nombre, s.tecnico_nombre) AS tecnico
         FROM solicitudes_presupuesto s
         LEFT JOIN empresas e ON e.id = s.empresa_id
         LEFT JOIN tecnicos t ON t.id = s.tecnico_id
         WHERE s.id_cliente = $1`,
        [idCliente]
    );
    if (!nota.rows[0]) return { error: 'No se pudo crear el presupuesto', status: 500 };
    return nota.rows[0];
}

module.exports = {
    interpretarFiltros,
    normalizarChecklist,
    topFallas,
    cumplimiento,
    variacion,
    armarVista,
    consultarAnalisis,
    crearPresupuestoDesdeComentario,
};
