const { programarRecorrido } = require('./ruta');
const { formulariosFijosDe } = require('./formularios');

function fechaISO(valor) {
    if (!valor) return null;
    if (typeof valor === 'string') return valor.slice(0, 10);
    // node-pg entrega un DATE a medianoche UTC. En Argentina eso es el día anterior si se lee en hora local.
    const medianocheUtc = valor.getUTCHours() === 0 && valor.getUTCMinutes() === 0 && valor.getUTCSeconds() === 0 && valor.getUTCMilliseconds() === 0;
    const anio = medianocheUtc ? valor.getUTCFullYear() : valor.getFullYear();
    const mes = String((medianocheUtc ? valor.getUTCMonth() : valor.getMonth()) + 1).padStart(2, '0');
    const dia = String(medianocheUtc ? valor.getUTCDate() : valor.getDate()).padStart(2, '0');
    return `${anio}-${mes}-${dia}`;
}

function hoyISO() {
    return fechaISO(new Date());
}

function sumarIntervalo(fecha, cantidad, tipo) {
    const [anio, mes, dia] = fechaISO(fecha).split('-').map(Number);
    const siguiente = new Date(anio, mes - 1, dia);
    const unidad = String(tipo || 'día').toLowerCase();
    if (unidad.startsWith('seman')) siguiente.setDate(siguiente.getDate() + 7 * cantidad);
    else if (unidad.startsWith('mes')) siguiente.setMonth(siguiente.getMonth() + cantidad);
    else if (unidad.startsWith('a')) siguiente.setFullYear(siguiente.getFullYear() + cantidad);
    else siguiente.setDate(siguiente.getDate() + cantidad);
    return fechaISO(siguiente);
}

// Fechas de las visitas que siguen a la primera. La primera es la orden original.
// "Nunca" arma seis meses hacia adelante para que el calendario las muestre ya.
function fechasSiguientes(plantilla, hoy = hoyISO()) {
    const inicio = fechaISO(plantilla.fecha_asignada);
    if (!inicio) return [];
    const paso = Math.max(1, Number(plantilla.recurrencia_valor) || 1);
    const condicion = plantilla.termina_condicion || 'Nunca';
    const ancla = hoy > inicio ? hoy : inicio;
    const topeNunca = sumarIntervalo(ancla, 6, 'mes');
    const repeticiones = Math.max(1, Number(plantilla.termina_repeticiones) || 1);
    const fin = fechaISO(plantilla.termina_fecha);
    const fechas = [];
    for (let indice = 1; indice < 400 && fechas.length < 120; indice++) {
        const fecha = sumarIntervalo(inicio, paso * indice, plantilla.recurrencia_tipo);
        if (condicion === 'Fecha') {
            if (!fin || fecha > fin) break;
        } else if (condicion === 'Repeticiones') {
            if (indice + 1 > repeticiones) break;
        } else if (fecha > topeNunca) {
            break;
        }
        fechas.push(fecha);
    }
    return fechas;
}

async function sincronizarSerie(pool, plantilla) {
    if (!plantilla || plantilla.orden_padre_id) return;
    if (!plantilla.es_recurrente || !plantilla.tecnico_id) {
        await pool.query(
            `DELETE FROM ordenes WHERE orden_padre_id = $1 AND estado IN ('Pendiente', 'Por asignar')`,
            [plantilla.id]
        );
        return;
    }
    const deseadas = new Set(fechasSiguientes(plantilla));
    // Formularios de cada visita: los de la orden madre o, si no tiene, los fijos de la empresa.
    let formularios = Array.isArray(plantilla.formularios) && plantilla.formularios.length ? plantilla.formularios : null;

    const hijos = await pool.query(
        `SELECT id, to_char(fecha_ocurrencia, 'YYYY-MM-DD') AS fecha, estado
         FROM ordenes WHERE orden_padre_id = $1`,
        [plantilla.id]
    );
    const ya = new Set();
    const dias = new Set();
    for (const hijo of hijos.rows) {
        if (hijo.fecha) ya.add(hijo.fecha);
        const pendiente = hijo.estado === 'Pendiente' || hijo.estado === 'Por asignar';
        if (pendiente && hijo.fecha && !deseadas.has(hijo.fecha)) {
            await pool.query('DELETE FROM ordenes WHERE id = $1', [hijo.id]);
            ya.delete(hijo.fecha);
            dias.add(hijo.fecha);
        }
    }
    for (const fecha of deseadas) {
        if (ya.has(fecha)) continue;
        if (formularios === null) formularios = await formulariosFijosDe(pool, plantilla.empresa_id);
        await pool.query(
            `INSERT INTO ordenes (
                tecnico_id, empresa_id, direccion_trabajo, descripcion_tarea, fecha_asignada, estado,
                es_recurrente, recurrencia_valor, recurrencia_tipo, hora_ejecucion,
                termina_condicion, termina_fecha, termina_repeticiones, orden_padre_id, fecha_ocurrencia,
                lat, lng, formulario_id, puntos, email_cliente, whatsapp_cliente, hora_hasta, formularios
            ) VALUES ($1,$2,$3,$4,$5,'Pendiente', FALSE, $6,$7,$8,$9,$10,$11,$12,$5,$13,$14,$15,
                      -- Sin checklist propio, cada visita del mes arranca con las tareas fijas de la empresa.
                      COALESCE($16::jsonb, (SELECT tareas_fijas FROM empresas WHERE id = $2)),$17,$18,$19,$20::jsonb)`,
            [
                plantilla.tecnico_id,
                plantilla.empresa_id,
                plantilla.direccion_trabajo,
                plantilla.descripcion_tarea,
                fecha,
                plantilla.recurrencia_valor,
                plantilla.recurrencia_tipo,
                plantilla.hora_ejecucion,
                plantilla.termina_condicion,
                plantilla.termina_fecha,
                plantilla.termina_repeticiones,
                plantilla.id,
                plantilla.lat,
                plantilla.lng,
                plantilla.formulario_id,
                plantilla.puntos ? JSON.stringify(plantilla.puntos) : null,
                plantilla.email_cliente,
                plantilla.whatsapp_cliente,
                plantilla.hora_hasta || null,
                formularios && formularios.length ? JSON.stringify(formularios) : null,
            ]
        );
        dias.add(fecha);
    }
    // Solo el contacto se copia siempre. El checklist y el horario de cada visita del mes se pueden
    // cambiar a mano en esa orden, así que no se pisan.
    await pool.query(
        `UPDATE ordenes SET email_cliente = $2, whatsapp_cliente = $3
         WHERE orden_padre_id = $1 AND estado IN ('Pendiente', 'Por asignar')`,
        [plantilla.id, plantilla.email_cliente, plantilla.whatsapp_cliente]
    );
    for (const fecha of dias) {
        programarRecorrido(pool, plantilla.tecnico_id, fecha);
    }
}

async function generarRecurrencias(pool, soloId) {
    if (soloId) {
        const una = await pool.query('SELECT * FROM ordenes WHERE id = $1', [soloId]);
        await sincronizarSerie(pool, una.rows[0]);
        return;
    }
    const plantillas = await pool.query(`
        SELECT * FROM ordenes
        WHERE es_recurrente = TRUE AND orden_padre_id IS NULL AND tecnico_id IS NOT NULL
    `);
    for (const plantilla of plantillas.rows) {
        await sincronizarSerie(pool, plantilla);
    }
}

module.exports = { generarRecurrencias, fechasSiguientes, sumarIntervalo };
