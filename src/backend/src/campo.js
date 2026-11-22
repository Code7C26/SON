const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { enviarCorreo } = require('./correo');
const { emailValido } = require('./auth');

function tokenNuevo() {
    return crypto.randomBytes(24).toString('hex');
}

function tokenValido(valor) {
    return typeof valor === 'string' && /^[a-f0-9]{48}$/.test(valor);
}

function diaValido(valor) {
    const texto = String(valor || '').slice(0, 10);
    return /^\d{4}-\d{2}-\d{2}$/.test(texto) ? texto : null;
}

function puntosDe(valor) {
    if (!Array.isArray(valor)) return [];
    return valor.map((punto) => String(punto || '').trim()).filter(Boolean).slice(0, 40);
}

function escapar(texto) {
    return String(texto ?? '').replace(/[&<>"']/g, (caracter) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[caracter]));
}

function basePublica(req) {
    const configurada = process.env.PUBLIC_URL;
    if (configurada) return configurada.replace(/\/$/, '');
    return `${req.protocol}://${req.get('host')}`;
}

function pagina(titulo, cuerpo) {
    return `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapar(titulo)}</title>
<style>
  body{margin:0;font-family:system-ui,sans-serif;background:#f4f4f4;color:#2e2e2e}
  main{max-width:520px;margin:0 auto;padding:32px 20px}
  h1{font-size:22px;margin:0 0 8px}
  p{line-height:1.5;color:#2e2e2e}
  a.btn,button{display:inline-block;margin-top:14px;background:#ff6147;color:#2e2e2e;text-decoration:none;font-weight:700;padding:12px 16px;border-radius:10px;border:0;font-size:16px;cursor:pointer}
  label{display:block;margin:10px 0}
  textarea{width:100%;box-sizing:border-box;margin-top:8px;padding:10px;border-radius:8px;border:1px solid #d4d4d4;background:#ffffff;color:#2e2e2e}
  .suave{color:#6a6a6a;font-size:14px}
</style></head><body><main>${cuerpo}</main></body></html>`;
}

async function leerAviso(pool, ordenId) {
    const fila = await pool.query(
        `SELECT o.id, o.estado, o.direccion_trabajo, o.token_seguimiento,
                to_char(o.fecha_asignada, 'YYYY-MM-DD') AS fecha,
                to_char(o.hora_ejecucion, 'HH24:MI') AS hora,
                e.razon_social AS cliente, e.email,
                o.email_cliente, o.whatsapp_cliente, o.puntos, o.descripcion_tarea, o.aviso_en,
                o.token_informe, o.informe_pdf,
                t.nombre AS tecnico, t.lat, t.lng, t.ubicacion_en
         FROM ordenes o
         LEFT JOIN empresas e ON e.id = o.empresa_id
         LEFT JOIN tecnicos t ON t.id = o.tecnico_id
         WHERE o.id = $1`,
        [ordenId]
    );
    return fila.rows[0] || null;
}

async function asegurarToken(pool, ordenId) {
    const actual = await pool.query('SELECT token_seguimiento FROM ordenes WHERE id = $1', [ordenId]);
    if (!actual.rows[0]) return null;
    if (actual.rows[0].token_seguimiento) return actual.rows[0].token_seguimiento;
    const nuevo = tokenNuevo();
    await pool.query('UPDATE ordenes SET token_seguimiento = $1 WHERE id = $2 AND token_seguimiento IS NULL', [nuevo, ordenId]);
    const guardado = await pool.query('SELECT token_seguimiento FROM ordenes WHERE id = $1', [ordenId]);
    return guardado.rows[0] ? guardado.rows[0].token_seguimiento : nuevo;
}

function listadoTareas(puntos, descripcion) {
    const lista = Array.isArray(puntos) ? puntos.map((punto) => String(punto || '').trim()).filter(Boolean) : [];
    const lineas = lista.length ? lista : String(descripcion || '').split('\n').map((linea) => linea.trim()).filter(Boolean);
    return lineas.length ? lineas.map((linea) => `• ${linea}`).join('\n') : 'La visita coordinada.';
}

function correoDe(valor) {
    const email = String(valor || '').trim().toLowerCase();
    if (!email) return null;
    return emailValido(email) ? email : null;
}

function numeroWhatsapp(valor) {
    let numero = String(valor || '').replace(/\D/g, '');
    if (numero.startsWith('00')) numero = numero.slice(2);
    if (numero.startsWith('0')) numero = `54${numero.slice(1)}`;
    if (numero.length === 10) numero = `549${numero}`;
    if (numero.startsWith('54') && !numero.startsWith('549') && numero.length === 12) numero = `549${numero.slice(2)}`;
    if (numero.length < 8 || numero.length > 15) return null;
    return numero;
}

function contactoDe(cuerpo) {
    const escritoMail = String(cuerpo && cuerpo.email_cliente || '').trim();
    const escritoWhatsapp = String(cuerpo && cuerpo.whatsapp_cliente || '').trim();
    return {
        email: correoDe(escritoMail),
        whatsapp: numeroWhatsapp(escritoWhatsapp),
        emailInvalido: Boolean(escritoMail) && !correoDe(escritoMail),
        whatsappInvalido: Boolean(escritoWhatsapp) && !numeroWhatsapp(escritoWhatsapp),
    };
}

function mensajeEnCamino(tecnico) {
    return `Hola, te hablamos de sima ambiente, el tecnico ${tecnico} esta en camino a realizar su trabajo! 🚨🛻`;
}

function botonesEncuesta(link) {
    const colores = ['#c45c5c', '#d4894a', '#c9a227', '#5a9e4a', '#1f8a4c'];
    const celdas = [1, 2, 3, 4, 5].map((n) => (
        `<td style="padding:4px"><a href="${link}?nota=${n}" style="display:inline-block;background:${colores[n - 1]};color:#ffffff;text-decoration:none;font-weight:700;font-size:18px;padding:12px 16px;border-radius:8px">${n}</a></td>`
    )).join('');
    return `<p>¿Cómo te fue? Tocá una nota:</p><table role="presentation" cellspacing="0" cellpadding="0"><tr>${celdas}</tr></table><p style="color:#667788;font-size:13px">1 es mal y 5 es muy bien. Con un toque queda registrada.</p>`;
}

function enlaceWhatsapp(numero, texto) {
    if (!numero) return null;
    return `https://wa.me/${numero}?text=${encodeURIComponent(texto)}`;
}

function raizPublica(base) {
    return (process.env.PUBLIC_URL || base || 'http://localhost:3000').replace(/\/$/, '');
}

// El PDF se guarda en "pendientes" y, cuando se copia a la carpeta del cliente, pasa a "enviados".
// La orden recuerda la primera ruta: si ya no está ahí, se busca en "enviados".
function rutaDelInforme(ruta) {
    if (!ruta) return null;
    if (fs.existsSync(ruta)) return ruta;
    const movida = ruta.replace(/([\\/])pendientes([\\/])/, '$1enviados$2');
    return movida !== ruta && fs.existsSync(movida) ? movida : null;
}

function fechaLegible(iso) {
    const partes = String(iso || '').split('-');
    if (partes.length !== 3) return iso || '';
    return `${partes[2]}/${partes[1]}/${partes[0]}`;
}

// Cuando se cierra un informe: anota la duración y, si el cliente tiene correo, le manda el PDF y la encuesta.
async function despuesDelInforme(pool, { ordenId, tecnicoId, cliente, inicio, fin, pdfPath, base }) {
    try {
        if (!ordenId) return;
        const tecnico = await pool.query('SELECT nombre FROM tecnicos WHERE id = $1', [tecnicoId]);
        const nombre = tecnico.rows[0] ? tecnico.rows[0].nombre : 'Técnico';
        const inicioFecha = inicio && !Number.isNaN(Date.parse(inicio)) ? new Date(inicio) : null;
        const finFecha = fin && !Number.isNaN(Date.parse(fin)) ? new Date(fin) : new Date();
        const minutos = inicioFecha ? Math.max(1, Math.round((finFecha - inicioFecha) / 60000)) : null;
        await pool.query(
            `INSERT INTO visitas (orden_id, tecnico_id, tecnico_nombre, cliente, inicio, fin, minutos)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (orden_id) DO UPDATE SET
                fin = EXCLUDED.fin,
                minutos = EXCLUDED.minutos,
                inicio = COALESCE(visitas.inicio, EXCLUDED.inicio)`,
            [ordenId, tecnicoId, nombre, cliente || null, inicioFecha, finFecha, minutos]
        );

        const datos = await leerAviso(pool, ordenId);
        // El PDF queda enlazado a la orden siempre (lo usa el acceso del cliente), tenga o no correo.
        if (datos && pdfPath && fs.existsSync(pdfPath)) {
            await pool.query(
                'UPDATE ordenes SET token_informe = COALESCE(token_informe, $1), informe_pdf = $2 WHERE id = $3',
                [tokenNuevo(), pdfPath, ordenId]
            );
        }
        const email = datos && (datos.email_cliente || datos.email);
        if (!datos || !email) return { whatsapp: null };
        let encuesta = await pool.query('SELECT token FROM encuestas WHERE orden_id = $1', [ordenId]);
        let tokenEncuesta = encuesta.rows[0] && encuesta.rows[0].token;
        if (!tokenEncuesta) {
            tokenEncuesta = tokenNuevo();
            await pool.query(
                'INSERT INTO encuestas (token, orden_id, cliente, email) VALUES ($1, $2, $3, $4) ON CONFLICT (orden_id) DO NOTHING',
                [tokenEncuesta, ordenId, datos.cliente, email]
            );
            encuesta = await pool.query('SELECT token FROM encuestas WHERE orden_id = $1', [ordenId]);
            tokenEncuesta = encuesta.rows[0] ? encuesta.rows[0].token : tokenEncuesta;
        }
        const tokenInforme = datos.token_informe || tokenNuevo();
        if (pdfPath && fs.existsSync(pdfPath)) {
            await pool.query(
                'UPDATE ordenes SET token_informe = COALESCE(token_informe, $1), informe_pdf = $2 WHERE id = $3',
                [tokenInforme, pdfPath, ordenId]
            );
        }
        const raiz = raizPublica(base);
        const link = `${raiz}/encuesta/${tokenEncuesta}`;
        const texto = `Hola, te hablamos de sima ambiente. Terminó la visita${datos.cliente ? ` en ${datos.cliente}` : ''}.\n\nEl informe va adjunto en PDF.\n\n¿Cómo te fue? Tocá una nota del 1 al 5:\n${[1, 2, 3, 4, 5].map((n) => `${n}: ${link}?nota=${n}`).join('\n')}\n`;
        if (email) {
            const adjuntos = pdfPath && fs.existsSync(pdfPath) ? [{ filename: 'Informe.pdf', path: pdfPath }] : [];
            try {
                const resultado = await enviarCorreo({
                    para: email,
                    asunto: `Informe de la visita — ${datos.cliente || 'SIMA Ambiente'}`,
                    texto,
                    html: `<p>Hola, te hablamos de <b>SIMA Ambiente</b>.</p><p>Terminó la visita. El informe va adjunto en PDF.</p>${botonesEncuesta(link)}`,
                    adjuntos,
                });
                if (resultado.enviado) {
                    await pool.query('UPDATE encuestas SET enviada_en = COALESCE(enviada_en, now()) WHERE orden_id = $1', [ordenId]);
                } else {
                    console.log('Correo al cliente no enviado:', resultado.motivo);
                }
            } catch (error) {
                console.log('Correo al cliente no enviado:', error.message);
            }
        }
        return { whatsapp: null, encuesta: link };
    } catch (error) {
        console.error('Después del informe:', error.message);
        return { whatsapp: null };
    }
}

async function avisarInicio(pool, ordenId, { forzar = false, base } = {}) {
    const datos = await leerAviso(pool, ordenId);
    if (!datos) return { error: 'Esa orden no existe', status: 404 };
    if (!datos.tecnico) return { error: 'Primero asigná un técnico', status: 400 };
    const email = datos.email_cliente || datos.email;
    if (!email) {
        if (forzar) return { error: 'Para que el aviso salga solo, cargá el correo del cliente en la orden.', status: 400 };
        return { ok: true, whatsapp: null };
    }
    const texto = mensajeEnCamino(datos.tecnico);
    let correo = null;
    if (forzar || !datos.aviso_en) {
        try {
            correo = await enviarCorreo({
                para: email,
                asunto: 'Tu técnico está en camino',
                texto,
                html: `<p>${escapar(texto)}</p>`,
            });
        } catch (error) {
            correo = { enviado: false, motivo: 'No se pudo enviar el correo.' };
            console.log('Correo al cliente no enviado:', error.message);
        }
        if (correo.enviado) await pool.query('UPDATE ordenes SET aviso_en = now() WHERE id = $1', [ordenId]);
    }
    return { ok: true, email, whatsapp: null, correo };
}

const avisosEnCurso = new Set();

function esHoraDeAvisar(fecha, hora, ahora = new Date()) {
    const partesFecha = String(fecha || '').split('-').map(Number);
    const partesHora = String(hora || '').split(':').map(Number);
    if (partesFecha.length < 3 || partesHora.length < 2) return false;
    if (partesFecha.some((n) => !Number.isInteger(n)) || partesHora.some((n) => !Number.isInteger(n))) return false;
    const programada = new Date(partesFecha[0], partesFecha[1] - 1, partesFecha[2], partesHora[0], partesHora[1], 0, 0);
    const falta = programada.getTime() - ahora.getTime();
    const unMinuto = 60 * 1000;
    const gracia = 2 * 60 * 1000;
    return falta <= unMinuto && falta > -gracia;
}

async function avisarLosQueEstanPorSalir(pool) {
    const ahora = new Date();
    const hoy = new Date(ahora.getFullYear(), ahora.getMonth(), ahora.getDate());
    const iso = (fecha) => `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, '0')}-${String(fecha.getDate()).padStart(2, '0')}`;
    const desde = new Date(hoy);
    desde.setDate(hoy.getDate() - 1);
    const hasta = new Date(hoy);
    hasta.setDate(hoy.getDate() + 1);
    const filas = await pool.query(
        `SELECT o.id, to_char(o.fecha_asignada, 'YYYY-MM-DD') AS fecha, to_char(o.hora_ejecucion, 'HH24:MI') AS hora
         FROM ordenes o
         WHERE o.estado = 'Pendiente'
           AND o.aviso_en IS NULL
           AND o.tecnico_id IS NOT NULL
           AND o.fecha_asignada BETWEEN $1::date AND $2::date
           AND o.hora_ejecucion IS NOT NULL
           -- Con rango horario el técnico maneja su horario: el aviso sale cuando toca "Ir" en la app.
           AND o.hora_hasta IS NULL`,
        [iso(desde), iso(hasta)]
    );
    for (const fila of filas.rows) {
        if (!esHoraDeAvisar(fila.fecha, fila.hora, ahora) || avisosEnCurso.has(fila.id)) continue;
        avisosEnCurso.add(fila.id);
        try {
            await avisarInicio(pool, fila.id, { forzar: false });
        } catch (error) {
            console.error('Aviso en camino:', error.message);
        } finally {
            avisosEnCurso.delete(fila.id);
        }
    }
}

function registrarRutasCampo(app, { pool, usuarioDelPanel, soloTecnico, buscarOCrearEmpresa }) {
    // Los formularios de control viven en src/formularios.js.

    app.post('/api/ordenes/pedir', soloTecnico, async (req, res) => {
        const nombre = String((req.body && req.body.nombre_cliente) || '').trim();
        const direccion = String((req.body && req.body.direccion) || '').trim();
        const descripcion = String((req.body && req.body.descripcion) || '').trim();
        const fecha = diaValido(req.body && req.body.fecha) || new Date().toISOString().slice(0, 10);
        if (!nombre) return res.status(400).json({ error: 'Escribí el cliente' });
        if (!direccion) return res.status(400).json({ error: 'Escribí la dirección' });
        try {
            const empresaId = await buscarOCrearEmpresa(nombre, direccion);
            const nueva = await pool.query(
                `INSERT INTO ordenes (
                    tecnico_id, empresa_id, direccion_trabajo, descripcion_tarea, fecha_asignada, estado, fecha_ocurrencia, pedida_por
                 ) VALUES (NULL, $1, $2, $3, $4, 'Por asignar', $4, $5) RETURNING id, estado`,
                [empresaId, direccion, descripcion || 'Pedido desde la calle', fecha, req.usuario.id]
            );
            res.json(nueva.rows[0]);
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo pedir la visita' });
        }
    });

    app.get('/informe/:token', async (req, res) => {
        if (!tokenValido(req.params.token)) return res.status(404).type('html').send(pagina('SON', '<h1>Este enlace no existe</h1>'));
        try {
            const fila = await pool.query('SELECT informe_pdf FROM ordenes WHERE token_informe = $1', [req.params.token]);
            const ruta = rutaDelInforme(fila.rows[0] && fila.rows[0].informe_pdf);
            const segura = ruta && !ruta.includes('..') && path.resolve(ruta).toLowerCase().endsWith('.pdf') && fs.existsSync(ruta);
            if (!segura) return res.status(404).type('html').send(pagina('SON', '<h1>El informe todavía no está</h1>'));
            res.download(path.resolve(ruta), 'Informe.pdf');
        } catch (error) {
            console.error(error);
            res.status(500).type('html').send(pagina('SON', '<h1>No se pudo abrir el informe</h1>'));
        }
    });

    app.post('/api/ordenes/:id/avisar', usuarioDelPanel, async (req, res) => {
        const id = Number(req.params.id);
        if (!Number.isInteger(id)) return res.status(400).json({ error: 'Orden inválida' });
        try {
            const aviso = await avisarInicio(pool, id, { forzar: true, base: basePublica(req) });
            if (aviso.error) return res.status(aviso.status || 400).json({ error: aviso.error });
            if (aviso.correo && aviso.correo.enviado === false) {
                return res.status(503).json({ error: aviso.correo.motivo });
            }
            res.json({
                ok: true,
                email: aviso.email,
                whatsapp: aviso.whatsapp,
                correo: aviso.correo && aviso.correo.enviado ? 'enviado' : (aviso.correo && aviso.correo.motivo) || null,
            });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo avisar al cliente' });
        }
    });

    app.get('/seguimiento/:token', async (req, res) => {
        if (!tokenValido(req.params.token)) return res.status(404).type('html').send(pagina('SON', '<h1>Este enlace no existe</h1>'));
        try {
            const fila = await pool.query(
                `SELECT o.estado, o.direccion_trabajo,
                        to_char(o.fecha_asignada, 'YYYY-MM-DD') AS fecha,
                        to_char(o.hora_ejecucion, 'HH24:MI') AS hora,
                        t.nombre AS tecnico, t.lat, t.lng, t.ubicacion_en
                 FROM ordenes o
                 LEFT JOIN tecnicos t ON t.id = o.tecnico_id
                 WHERE o.token_seguimiento = $1`,
                [req.params.token]
            );
            const datos = fila.rows[0];
            if (!datos) return res.status(404).type('html').send(pagina('SON', '<h1>Este enlace no existe</h1>'));
            const cuando = [fechaLegible(datos.fecha), datos.hora].filter(Boolean).join(' a las ');
            let extra = '<p>Cuando salga hacia tu dirección, vas a verlo acá.</p>';
            if (datos.estado === 'Completada') {
                extra = '<p>La visita ya terminó. Gracias.</p>';
            } else if (datos.estado === 'En progreso' && datos.lat != null && datos.lng != null) {
                const reciente = datos.ubicacion_en && (Date.now() - new Date(datos.ubicacion_en).getTime()) < 3 * 60 * 60 * 1000;
                if (reciente) {
                    const mapa = `https://www.google.com/maps?q=${datos.lat},${datos.lng}`;
                    extra = `<p>Ya está en camino.</p><a class="btn" href="${mapa}">Ver en el mapa</a><p class="suave">La ubicación se actualiza sola.</p><script>setTimeout(function(){location.reload()},30000)</script>`;
                }
            }
            res.type('html').send(pagina('Tu visita', `<h1>${escapar(datos.tecnico || 'Tu visita')}</h1><p>${escapar(cuando || 'Horario a confirmar')}</p><p>${escapar(datos.direccion_trabajo || '')}</p>${extra}`));
        } catch (error) {
            console.error(error);
            res.status(500).type('html').send(pagina('SON', '<h1>No se pudo abrir la visita</h1>'));
        }
    });

    app.get('/encuesta/:token', async (req, res) => {
        if (!tokenValido(req.params.token)) return res.status(404).type('html').send(pagina('SON', '<h1>Este enlace no existe</h1>'));
        try {
            const nota = Number(req.query.nota);
            if (Number.isInteger(nota) && nota >= 1 && nota <= 5) {
                await pool.query(
                    'UPDATE encuestas SET puntaje = $1, respondida_en = now() WHERE token = $2 AND puntaje IS NULL',
                    [nota, req.params.token]
                );
            }
            const fila = await pool.query('SELECT puntaje, comentario, cliente FROM encuestas WHERE token = $1', [req.params.token]);
            if (!fila.rows[0]) return res.status(404).type('html').send(pagina('SON', '<h1>Este enlace no existe</h1>'));
            const datos = fila.rows[0];
            if (datos.puntaje != null && datos.comentario) {
                return res.type('html').send(pagina('Gracias', '<h1>Gracias</h1><p>Ya recibimos tu respuesta.</p>'));
            }
            if (datos.puntaje != null) {
                return res.type('html').send(pagina('Gracias', `
                    <h1>Gracias</h1>
                    <p>Anotamos un <b>${datos.puntaje}</b>.</p>
                    <form id="encuesta">
                      <textarea rows="4" maxlength="1000" placeholder="Si querés, contanos algo más"></textarea>
                      <button type="submit">Enviar comentario</button>
                      <p class="suave" id="aviso"></p>
                    </form>
                    <script>
                      document.getElementById('encuesta').onsubmit = async function (evento) {
                        evento.preventDefault();
                        var respuesta = await fetch(location.pathname, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ comentario: document.querySelector('textarea').value }) });
                        var aviso = document.getElementById('aviso');
                        if (respuesta.ok) document.querySelector('main').innerHTML = '<h1>Gracias</h1><p>Recibimos tu comentario.</p>';
                        else aviso.textContent = 'No se pudo enviar. Probá de nuevo.';
                      };
                    </script>`));
            }
            const botones = [1, 2, 3, 4, 5].map((n) => `<a class="btn" href="?nota=${n}" style="margin-right:8px">${n}</a>`).join(' ');
            res.type('html').send(pagina('¿Cómo te fue?', `
                <h1>¿Cómo te fue con la visita?</h1>
                <p>${escapar(datos.cliente || '')}</p>
                <p>Tocá una nota. 1 es mal y 5 es muy bien.</p>
                <p>${botones}</p>`));
        } catch (error) {
            console.error(error);
            res.status(500).type('html').send(pagina('SON', '<h1>No se pudo abrir la encuesta</h1>'));
        }
    });

    app.post('/encuesta/:token', async (req, res) => {
        if (!tokenValido(req.params.token)) return res.status(404).json({ error: 'Este enlace no existe' });
        const puntaje = Number(req.body && req.body.puntaje);
        const comentario = String((req.body && req.body.comentario) || '').trim().slice(0, 1000);
        const notaValida = Number.isInteger(puntaje) && puntaje >= 1 && puntaje <= 5;
        try {
            const actual = await pool.query('SELECT puntaje, comentario FROM encuestas WHERE token = $1', [req.params.token]);
            if (!actual.rows[0]) return res.status(404).json({ error: 'Este enlace no existe' });
            if (actual.rows[0].puntaje != null) {
                if (!comentario || actual.rows[0].comentario) return res.status(409).json({ error: 'Esta encuesta ya fue respondida' });
                await pool.query('UPDATE encuestas SET comentario = $1 WHERE token = $2', [comentario, req.params.token]);
                return res.json({ ok: true });
            }
            if (!notaValida) return res.status(400).json({ error: 'Elegí una nota del 1 al 5' });
            await pool.query(
                'UPDATE encuestas SET puntaje = $1, comentario = $2, respondida_en = now() WHERE token = $3 AND puntaje IS NULL',
                [puntaje, comentario || null, req.params.token]
            );
            res.json({ ok: true });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar la respuesta' });
        }
    });
}

module.exports = {
    registrarRutasCampo, despuesDelInforme, diaValido, puntosDe, contactoDe, avisarInicio, avisarLosQueEstanPorSalir,
    esHoraDeAvisar, numeroWhatsapp, listadoTareas, pagina, escapar, tokenNuevo, tokenValido, rutaDelInforme, raizPublica,
};
