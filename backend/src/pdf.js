const PDFDocument = require('pdfkit');
const fs = require('fs');
const path = require('path');

// --- Diseño del informe (membrete de Sima, colores y datos de contacto) ---
// Para cambiar el pie de página o los colores se edita solo esta parte.
const DISENO = {
    colorTexto: '#003024', // verde oscuro
    colorAcento: '#7AEB67', // verde claro (íconos del pie)
    colorFondo: '#FFFFFF', // fondo de la página
    colorBorde: '#D5D8D6',
    contacto: {
        telefono: '351 2420841',
        email: 'info@simaambiente.com',
        web: 'simaambiente.com',
    },
};

const CARPETA_ASSETS = path.join(__dirname, '..', 'assets');
const RUTA_LOGO = path.join(CARPETA_ASSETS, 'pdf', 'logo.png');
const FUENTES = {
    regular: path.join(CARPETA_ASSETS, 'fonts', 'BwGradualDEMO-Regular.otf'),
    media: path.join(CARPETA_ASSETS, 'fonts', 'BwGradualDEMO-Medium.otf'),
    negrita: path.join(CARPETA_ASSETS, 'fonts', 'BwGradualDEMO-Bold.otf'),
};

// Medidas de la hoja A4 (en puntos)
const ANCHO = 595.28;
const ALTO = 841.89;
const MARGEN_X = 55;
const MARGEN_SUPERIOR = 118; // deja libre el membrete
const MARGEN_INFERIOR = 135; // deja libre el pie de página
const ANCHO_UTIL = ANCHO - MARGEN_X * 2;

function bufferImagen(dataUrl) {
    if (!dataUrl || typeof dataUrl !== 'string') return null;
    const coincidencia = dataUrl.match(/^data:image\/[a-zA-Z0-9.+-]+;base64,(.+)$/);
    const base64 = coincidencia ? coincidencia[1] : dataUrl;
    try {
        const buffer = Buffer.from(base64, 'base64');
        return buffer.length ? buffer : null;
    } catch {
        return null;
    }
}

function fechaLegible(valor) {
    const fecha = valor ? new Date(valor) : null;
    if (!fecha || Number.isNaN(fecha.getTime())) return null;
    // Siempre en 24 horas: sin esto, algunas versiones de Node escriben "01:03" para la una de la tarde.
    return fecha.toLocaleString('es-AR', { timeZone: 'America/Argentina/Buenos_Aires', hourCycle: 'h23' });
}

function duracionLegible(inicio, fin) {
    const a = inicio ? new Date(inicio).getTime() : NaN;
    const b = fin ? new Date(fin).getTime() : NaN;
    if (Number.isNaN(a) || Number.isNaN(b) || b < a) return null;
    const minutos = Math.round((b - a) / 60000);
    return `${Math.floor(minutos / 60)} h ${String(minutos % 60).padStart(2, '0')} min`;
}

// --- Íconos del pie (dibujados, no hacen falta archivos) ---
function iconoWhatsapp(doc, x, y) {
    doc.save().lineWidth(1).strokeColor(DISENO.colorAcento);
    doc.circle(x + 6, y + 6, 5.5).stroke();
    // auricular
    doc.moveTo(x + 4, y + 3.5).bezierCurveTo(x + 3.5, y + 7, x + 5.5, y + 8.5, x + 8.5, y + 8.5).stroke();
    doc.restore();
}

function iconoMail(doc, x, y) {
    doc.save().lineWidth(1).strokeColor(DISENO.colorAcento);
    doc.roundedRect(x, y + 1.5, 12, 9, 1).stroke();
    doc.moveTo(x, y + 2.5).lineTo(x + 6, y + 7).lineTo(x + 12, y + 2.5).stroke();
    doc.restore();
}

function iconoWeb(doc, x, y) {
    doc.save().lineWidth(1).strokeColor(DISENO.colorAcento);
    doc.circle(x + 6, y + 6, 5.5).stroke();
    doc.ellipse(x + 6, y + 6, 2.4, 5.5).stroke();
    doc.moveTo(x + 0.5, y + 6).lineTo(x + 11.5, y + 6).stroke();
    doc.restore();
}

// Hojas de anexo (las planillas de los formularios): membrete chico para dejar lugar a la planilla.
function dibujarHojaAnexo(doc, numero, fuentes) {
    const margenes = doc.page.margins;
    const inferiorOriginal = margenes.bottom;
    margenes.bottom = 0;
    const ancho = doc.page.width;
    const alto = doc.page.height;
    doc.save();
    doc.rect(0, 0, ancho, alto).fill(DISENO.colorFondo);
    if (fs.existsSync(RUTA_LOGO)) doc.image(RUTA_LOGO, ancho - 30 - 90, 12, { width: 90 });
    doc.fillColor(DISENO.colorTexto).font(fuentes.regular).fontSize(9)
        .text(String(numero).padStart(2, '0'), ancho - 30 - 60, alto - 26, { width: 60, align: 'right', lineBreak: false });
    doc.restore();
    margenes.bottom = inferiorOriginal;
    doc.fillColor(DISENO.colorTexto);
}

// Membrete, fondo y pie de página: se dibujan en cada hoja nueva.
function dibujarHoja(doc, numero, fuentes, hayFuentes) {
    const margenes = doc.page.margins;
    const inferiorOriginal = margenes.bottom;
    margenes.bottom = 0; // para poder escribir en el pie sin que se abra otra hoja
    // Si un texto largo salta de hoja, tiene que seguir con la misma letra y tamaño.
    const fuenteAntes = doc._font;
    const tamanoAntes = doc._fontSize;

    doc.save();
    doc.rect(0, 0, ANCHO, ALTO).fill(DISENO.colorFondo);

    // Membrete
    if (fs.existsSync(RUTA_LOGO)) {
        const anchoLogo = 215;
        doc.image(RUTA_LOGO, (ANCHO - anchoLogo) / 2, 26, { width: anchoLogo });
    } else {
        doc.fillColor(DISENO.colorTexto).font(fuentes.negrita).fontSize(22).text('SIMA', 0, 40, { width: ANCHO, align: 'center', lineBreak: false });
    }

    // Pie: contacto comercial y número de hoja
    const c = DISENO.contacto;
    const x0 = 42;
    let y = ALTO - 118;
    doc.fillColor(DISENO.colorTexto).font(fuentes.regular).fontSize(10);
    doc.text('Contacto Comercial', x0, y, { underline: true, lineBreak: false });
    y += 20;
    iconoWhatsapp(doc, x0, y - 1);
    doc.fillColor(DISENO.colorTexto).fontSize(10).text(c.telefono, x0 + 22, y, { lineBreak: false });
    y += 19;
    iconoMail(doc, x0, y - 1);
    doc.fillColor(DISENO.colorTexto).text(c.email, x0 + 22, y, { lineBreak: false });
    y += 19;
    iconoWeb(doc, x0, y - 1);
    doc.fillColor(DISENO.colorTexto).text(c.web, x0 + 22, y, { lineBreak: false });
    doc.fillColor(DISENO.colorTexto).fontSize(10).text(String(numero).padStart(2, '0'), ANCHO - MARGEN_X - 60, ALTO - 62, { width: 60, align: 'right', lineBreak: false });
    doc.restore();

    margenes.bottom = inferiorOriginal;
    doc._font = fuenteAntes;
    doc._fontSize = tamanoAntes;
    doc.fillColor(DISENO.colorTexto);
    doc.x = MARGEN_X;
    doc.y = MARGEN_SUPERIOR;
}

// Fecha corta en hora de Argentina: 11/11/2026.
function fechaCorta(valor) {
    const fecha = valor ? new Date(valor) : new Date();
    if (Number.isNaN(fecha.getTime())) return null;
    return fecha.toLocaleDateString('es-AR', { timeZone: 'America/Argentina/Buenos_Aires', day: '2-digit', month: '2-digit', year: 'numeric' });
}

// Párrafo con el que arranca todo informe (antes lo escribían a mano en cada visita).
function textoEncabezado({ cliente, direccion, fin }) {
    const fecha = fechaCorta(fin);
    const lugar = String(direccion || '').trim();
    return `En el día de la fecha${fecha ? `, ${fecha},` : ''} se realizó la visita a ${String(cliente || 'la empresa').trim()}` +
        `${lugar ? `, sita en ${lugar},` : ''} en la cual se llevaron a cabo las tareas que se detallan a continuación. ` +
        'Al final se dejan asentadas las observaciones de la visita.';
}

// --- Planilla igual al Excel, completada (va como anexo al final del informe) ---
const COLOR_CARGADO = '#1F4E9A'; // lo que escribió el técnico, en azul como birome

function anchoDeBorde(estilo) {
    if ([2, 8, 10, 12].includes(estilo)) return 1.1; // medio
    if ([5, 6].includes(estilo)) return 1.6; // grueso o doble
    return 0.5; // fino, punteado, etc.
}

function fechaDeCasillero(iso) {
    const partes = String(iso || '').split('-');
    return partes.length === 3 ? `${partes[2]}/${partes[1]}/${partes[0]}` : String(iso || '');
}

function dibujarPlanillaExcel(doc, formulario, { cliente, fin, fuentes }) {
    const d = formulario.definicion;
    const anchoTotal = d.anchos.reduce((a, b) => a + b, 0);
    const altoTotal = d.altos.reduce((a, b) => a + b, 0);
    if (!anchoTotal || !altoTotal) return;
    const horizontal = anchoTotal > altoTotal;
    doc.addPage({ size: 'A4', layout: horizontal ? 'landscape' : 'portrait', margins: { top: 46, bottom: 34, left: 30, right: 30 } });
    const anchoHoja = doc.page.width;
    const altoHoja = doc.page.height;

    doc.font(fuentes.media).fontSize(9).fillColor(DISENO.colorTexto)
        .text(`Anexo · ${formulario.nombre}`, 30, 20, { width: anchoHoja - 160, lineBreak: false });
    const espacioObservacion = formulario.observacion ? 34 : 0;
    const escala = Math.min((anchoHoja - 60) / anchoTotal, (altoHoja - 46 - 34 - espacioObservacion) / altoTotal, 1.3);
    const x0 = 30 + ((anchoHoja - 60) - anchoTotal * escala) / 2;
    const y0 = 46;
    const xs = [x0];
    d.anchos.forEach((ancho) => xs.push(xs[xs.length - 1] + ancho * escala));
    const ys = [y0];
    d.altos.forEach((alto) => ys.push(ys[ys.length - 1] + alto * escala));
    const caja = (celda) => {
        const f2 = celda.f2 ?? celda.f;
        const c2 = celda.c2 ?? celda.c;
        return { x: xs[celda.c], y: ys[celda.f], w: xs[c2 + 1] - xs[celda.c], h: ys[f2 + 1] - ys[celda.f] };
    };
    const escribir = (texto, { x, y, w, h }, celda, { color = DISENO.colorTexto, negrita = false, tamano = null } = {}) => {
        if (!texto || w < 2 || h < 2) return;
        const relleno = 1.5 * escala;
        let z = Math.max(3.5, (tamano || celda.z || 10) * escala);
        doc.font(negrita || celda.n ? fuentes.negrita : fuentes.regular).fillColor(color);
        const giro = celda.r || 0;
        const vertical = giro === 90 || giro === -90;
        const anchoTexto = Math.max(1, (vertical ? h : w) - relleno * 2);
        const altoTexto = Math.max(1, (vertical ? w : h) - relleno * 2);
        const contenido = giro === 255 ? String(texto).split('').join('\n') : String(texto);
        // Si no entra, se achica la letra (como hace Excel al imprimir "ajustar").
        doc.fontSize(z);
        while (z > 3.5 && doc.heightOfString(contenido, { width: anchoTexto }) > altoTexto) {
            z -= 0.5;
            doc.fontSize(z);
        }
        const altoReal = Math.min(altoTexto, doc.heightOfString(contenido, { width: anchoTexto }));
        const desplazamiento = celda.v === 't' ? 0 : celda.v === 'c' ? (altoTexto - altoReal) / 2 : altoTexto - altoReal;
        const opciones = { width: anchoTexto, height: altoTexto, align: { l: 'left', c: 'center', r: 'right' }[celda.h] || 'left', lineBreak: true, ellipsis: true };
        doc.save();
        if (giro === 90) {
            doc.translate(x + relleno + desplazamiento, y + h - relleno).rotate(-90);
            doc.text(contenido, 0, 0, opciones);
        } else if (giro === -90) {
            doc.translate(x + w - relleno - desplazamiento, y + relleno).rotate(90);
            doc.text(contenido, 0, 0, opciones);
        } else {
            doc.text(contenido, x + relleno, y + relleno + desplazamiento, opciones);
        }
        doc.restore();
    };

    // Celdas: bordes y textos del Excel ("Empresa:" y "Fecha:" se completan solos).
    const porPosicion = new Map();
    for (const celda of d.celdas) {
        porPosicion.set(`${celda.f},${celda.c}`, celda);
        const c = caja(celda);
        if (!c.w || !c.h) continue;
        const lados = [
            [celda.b[0], c.x, c.y, c.x, c.y + c.h], [celda.b[1], c.x + c.w, c.y, c.x + c.w, c.y + c.h],
            [celda.b[2], c.x, c.y, c.x + c.w, c.y], [celda.b[3], c.x, c.y + c.h, c.x + c.w, c.y + c.h],
        ];
        for (const [estilo, ax, ay, bx, by] of lados) {
            if (!estilo) continue;
            doc.save().lineWidth(anchoDeBorde(estilo)).strokeColor('#222222').moveTo(ax, ay).lineTo(bx, by).stroke().restore();
        }
        let texto = celda.t || '';
        if (celda.auto === 'empresa' && cliente) texto = `${texto} ${cliente}`;
        if (celda.auto === 'fecha') texto = `${texto} ${fechaCorta(fin) || ''}`;
        escribir(texto, c, celda);
    }

    // Lo que cargó el técnico.
    for (const campo of d.campos) {
        const valor = (formulario.valores || {})[`${campo.f},${campo.c}`];
        if (!valor) continue;
        const celda = porPosicion.get(`${campo.f},${campo.c}`) || { f: campo.f, c: campo.c, b: [0, 0, 0, 0] };
        const c = caja(celda);
        const texto = campo.tipo === 'fecha' ? fechaDeCasillero(valor) : valor;
        escribir(texto, c, { ...celda, h: campo.tipo === 'marca' ? 'c' : celda.h || 'c', v: 'c', r: 0 }, {
            color: COLOR_CARGADO,
            negrita: campo.tipo === 'marca',
            tamano: Math.min(11, (celda.z || 10)),
        });
    }

    if (formulario.observacion) {
        doc.font(fuentes.regular).fontSize(9).fillColor(DISENO.colorTexto)
            .text(`Observaciones: ${formulario.observacion}`, 30, ys[ys.length - 1] + 8, { width: anchoHoja - 60, height: 30, ellipsis: true });
    }
}

// "Control de tableros: 3 tableros revisados" / "Control de almacenaje: 12 de 13 puntos respondidos".
function resumenDeFormulario(formulario) {
    const d = formulario.definicion || {};
    if (d.tipo === 'excel') {
        const filas = formulario.filasCompletadas || 0;
        return filas ? `${formulario.nombre}: completado (${filas} ${filas === 1 ? 'renglón' : 'renglones'}, ver anexo)` : `${formulario.nombre}: sin completar`;
    }
    if (d.tipo === 'planilla') {
        const n = formulario.filas ? formulario.filas.length : 0;
        const elemento = String(d.elemento || 'elemento').toLowerCase();
        // "extintor" -> "extintores", "puerta o salida" -> "puertas o salidas".
        const plural = elemento.split(' ').map((palabra) => (['o', 'y', 'de'].includes(palabra) || /s$/.test(palabra) ? palabra : /[aeiouáéó]$/.test(palabra) ? `${palabra}s` : `${palabra}es`)).join(' ');
        return `${formulario.nombre}: ${n} ${n === 1 ? `${elemento} revisado` : `${plural} revisados`}`;
    }
    const total = (d.preguntas || []).filter((p) => !p.seccion).length;
    return `${formulario.nombre}: ${formulario.contestadas || 0} de ${total} puntos controlados`;
}

function valorLegible(campo, valor) {
    if (valor === null || valor === undefined || valor === '') return '—';
    if (campo && campo.tipo === 'fecha') {
        const partes = String(valor).split('-');
        return partes.length === 3 ? `${partes[2]}/${partes[1]}/${partes[0]}` : String(valor);
    }
    return String(valor);
}

function crearInforme({ destino, cliente, tecnico, matricula, direccion, comentarios, latitud, longitud, firmaTecnico, firmaCliente, evidencias, checklist, formularios, inicio, fin }) {
    const doc = new PDFDocument({
        size: 'A4',
        margins: { top: MARGEN_SUPERIOR, bottom: MARGEN_INFERIOR, left: MARGEN_X, right: MARGEN_X },
        autoFirstPage: false,
        info: { Title: 'Informe de visita', Author: 'Sima' },
    });
    const archivo = fs.createWriteStream(destino);
    doc.pipe(archivo);

    // Fuentes de la marca (si faltan, se usan las del sistema)
    const hayFuentes = Object.values(FUENTES).every((ruta) => fs.existsSync(ruta));
    const fuentes = hayFuentes ? { regular: 'regular', media: 'media', negrita: 'negrita' } : { regular: 'Helvetica', media: 'Helvetica-Bold', negrita: 'Helvetica-Bold' };
    if (hayFuentes) for (const [nombre, ruta] of Object.entries(FUENTES)) doc.registerFont(nombre, ruta);

    let hojas = 0;
    let enAnexo = false;
    doc.on('pageAdded', () => {
        hojas += 1;
        if (enAnexo) dibujarHojaAnexo(doc, hojas, fuentes);
        else dibujarHoja(doc, hojas, fuentes, hayFuentes);
    });
    doc.addPage();

    const limiteInferior = () => ALTO - MARGEN_INFERIOR;
    // Si lo que sigue no entra en la hoja, pasa a la siguiente.
    const asegurarEspacio = (alto) => {
        if (doc.y + alto > limiteInferior()) doc.addPage();
    };

    // Título
    doc.fillColor(DISENO.colorTexto).font(fuentes.regular).fontSize(30);
    doc.text('Informe de visita', MARGEN_X, 88, { width: ANCHO_UTIL, align: 'center', underline: true });
    doc.y += 22;

    // Datos de la visita
    const campo = (etiqueta, valor) => {
        asegurarEspacio(26);
        doc.fontSize(14.5).font(fuentes.media).fillColor(DISENO.colorTexto).text(`${etiqueta}: `, MARGEN_X, doc.y, { continued: true, width: ANCHO_UTIL });
        doc.font(fuentes.regular).text(String(valor), { width: ANCHO_UTIL });
        doc.y += 7;
    };
    const textoInicio = fechaLegible(inicio);
    const textoFin = fechaLegible(fin) || fechaLegible(new Date());
    campo('Empresa', cliente || 'N/A');
    campo('Técnico asignado', tecnico || 'N/A');
    if (textoInicio) campo('Inicio', textoInicio);
    campo(textoInicio ? 'Fin' : 'Fecha', textoFin);
    const duracion = duracionLegible(inicio, fin);
    if (duracion) campo('Duración', duracion);
    campo('Dirección', direccion || 'N/A');
    if (latitud != null && longitud != null) campo('Check-in GPS', `${latitud}, ${longitud}`);

    // El título nunca queda solo al final de una hoja: pasa a la siguiente junto con lo que le sigue.
    const titulo = (texto, espacioQueSigue = 40) => {
        asegurarEspacio(espacioQueSigue + 30);
        doc.y += 10;
        doc.font(fuentes.negrita).fontSize(16).fillColor(DISENO.colorTexto).text(`${texto}:`, MARGEN_X, doc.y, { underline: true });
        doc.y += 8;
    };

    // Encabezado fijo: "En el día de la fecha se realizó la visita a..."
    asegurarEspacio(60);
    doc.y += 6;
    doc.font(fuentes.regular).fontSize(13).fillColor(DISENO.colorTexto)
        .text(textoEncabezado({ cliente, direccion, fin }), MARGEN_X, doc.y, { width: ANCHO_UTIL, align: 'justify' });
    doc.y += 4;

    // Tareas: el checklist y, además, cada formulario de control completado.
    titulo('Tareas', 40);
    const completados = (Array.isArray(formularios) ? formularios : []).filter((f) => f && f.definicion);
    const items = [
        ...(Array.isArray(checklist) ? checklist : []),
        ...completados.map((f) => ({ tarea: resumenDeFormulario(f), hecho: (f.contestadas || 0) > 0 })),
    ];
    doc.font(fuentes.regular).fontSize(13);
    if (items.length === 0) {
        doc.text('Sin tareas cargadas.', MARGEN_X, doc.y);
    } else {
        for (const item of items) {
            const texto = String(item.tarea || '');
            const alto = Math.max(16, doc.heightOfString(texto, { width: ANCHO_UTIL - 26 }));
            asegurarEspacio(alto + 8);
            const y = doc.y;
            // casilla con tilde
            doc.save().lineWidth(1).strokeColor(DISENO.colorTexto).roundedRect(MARGEN_X, y + 1.5, 11, 11, 2).stroke();
            if (item.hecho) {
                doc.lineWidth(1.8).strokeColor(DISENO.colorTexto).moveTo(MARGEN_X + 2.5, y + 7.5).lineTo(MARGEN_X + 5, y + 10).lineTo(MARGEN_X + 9, y + 4).stroke();
            }
            doc.restore();
            doc.fillColor(DISENO.colorTexto).font(fuentes.regular).fontSize(13).text(texto, MARGEN_X + 22, y, { width: ANCHO_UTIL - 26 });
            doc.y = y + alto + 7;
        }
    }

    // Detalle de cada formulario de control (los de tipo Excel van como anexo, al final)
    for (const formulario of completados.filter((f) => f.definicion.tipo !== 'excel')) {
        const d = formulario.definicion;
        titulo(formulario.nombre, 60);
        if (d.tipo === 'planilla') {
            const filas = formulario.filas || [];
            if (!filas.length) {
                doc.font(fuentes.regular).fontSize(11.5).fillColor(DISENO.colorTexto).text('No se cargaron elementos.', MARGEN_X, doc.y);
            }
            filas.forEach((fila, i) => {
                const nombre = valorLegible(d.campos[0], fila.valores[0]);
                asegurarEspacio(60);
                doc.font(fuentes.media).fontSize(12).fillColor(DISENO.colorTexto)
                    .text(`${d.elemento || 'Elemento'} ${i + 1}${nombre !== '—' ? `: ${nombre}` : ''}`, MARGEN_X, doc.y, { width: ANCHO_UTIL });
                doc.y += 3;
                // Los datos en dos columnas para que no ocupen tanto.
                const anchoColumna = (ANCHO_UTIL - 16) / 2;
                const pares = d.campos.slice(1).map((campo, k) => ({ campo, valor: valorLegible(campo, fila.valores[k + 1]) }));
                for (let k = 0; k < pares.length; k += 2) {
                    const fragmentos = pares.slice(k, k + 2).map(({ campo, valor }) => `${campo.etiqueta}: ${valor}`);
                    doc.font(fuentes.regular).fontSize(10);
                    const alto = Math.max(...fragmentos.map((t) => doc.heightOfString(t, { width: anchoColumna })));
                    asegurarEspacio(alto + 4);
                    const y = doc.y;
                    fragmentos.forEach((t, j) => {
                        doc.font(fuentes.regular).fontSize(10).fillColor(DISENO.colorTexto).text(t, MARGEN_X + 8 + j * (anchoColumna + 8), y, { width: anchoColumna });
                    });
                    doc.y = y + alto + 3;
                }
                if (fila.obs) {
                    asegurarEspacio(20);
                    doc.font(fuentes.regular).fontSize(10).fillColor(DISENO.colorTexto).text(`Observación: ${fila.obs}`, MARGEN_X + 8, doc.y, { width: ANCHO_UTIL - 8 });
                }
                doc.y += 6;
            });
        } else {
            const columnas = d.columnas && d.columnas.length ? d.columnas : null;
            const anchoRespuesta = columnas ? Math.min(220, 60 * columnas.length) : 70;
            const anchoPregunta = ANCHO_UTIL - anchoRespuesta - 10;
            if (columnas) {
                asegurarEspacio(20);
                const y = doc.y;
                doc.font(fuentes.media).fontSize(9).fillColor(DISENO.colorTexto);
                columnas.forEach((col, j) => doc.text(col, MARGEN_X + anchoPregunta + 10 + j * (anchoRespuesta / columnas.length), y, { width: anchoRespuesta / columnas.length, align: 'center' }));
                doc.y = y + 16;
            }
            d.preguntas.forEach((pregunta, i) => {
                if (pregunta.seccion) {
                    asegurarEspacio(34);
                    doc.y += 4;
                    doc.font(fuentes.media).fontSize(11.5).fillColor(DISENO.colorTexto).text(pregunta.texto, MARGEN_X, doc.y, { width: ANCHO_UTIL });
                    doc.y += 3;
                    return;
                }
                const respuesta = (formulario.respuestas || [])[i] || { valores: [] };
                doc.font(fuentes.regular).fontSize(10.5);
                const alto = Math.max(14, doc.heightOfString(pregunta.texto, { width: anchoPregunta }));
                asegurarEspacio(alto + (respuesta.obs ? 16 : 4));
                const y = doc.y;
                doc.fillColor(DISENO.colorTexto).text(pregunta.texto, MARGEN_X, y, { width: anchoPregunta });
                const valores = columnas ? columnas.map((_, j) => respuesta.valores[j]) : [respuesta.valores[0]];
                valores.forEach((valor, j) => {
                    const ancho = anchoRespuesta / valores.length;
                    doc.font(fuentes.media).fontSize(10.5).text(valor || '—', MARGEN_X + anchoPregunta + 10 + j * ancho, y, { width: ancho, align: 'center' });
                });
                doc.y = y + alto + 2;
                if (respuesta.obs) {
                    doc.font(fuentes.regular).fontSize(9.5).fillColor(DISENO.colorTexto).text(`Observación: ${respuesta.obs}`, MARGEN_X + 10, doc.y, { width: anchoPregunta });
                }
                doc.y += 3;
            });
        }
        if (formulario.observacion) {
            asegurarEspacio(24);
            doc.y += 2;
            doc.font(fuentes.regular).fontSize(10.5).fillColor(DISENO.colorTexto).text(`Observaciones: ${formulario.observacion}`, MARGEN_X, doc.y, { width: ANCHO_UTIL });
            doc.y += 4;
        }
    }

    // Observaciones
    titulo('Observaciones');
    doc.font(fuentes.regular).fontSize(13).fillColor(DISENO.colorTexto).text(comentarios || 'Sin observaciones.', MARGEN_X, doc.y, { width: ANCHO_UTIL });
    doc.y += 8;

    // Evidencias: fotos de a dos por fila
    const fotos = (Array.isArray(evidencias) ? evidencias : []).map(bufferImagen).filter(Boolean);
    if (fotos.length) {
        const anchoFoto = (ANCHO_UTIL - 14) / 2;
        const altoFoto = 165;
        titulo('Evidencias', altoFoto + 24);
        for (let i = 0; i < fotos.length; i += 2) {
            asegurarEspacio(altoFoto + 24);
            const y = doc.y;
            for (let j = 0; j < 2 && i + j < fotos.length; j++) {
                const x = MARGEN_X + j * (anchoFoto + 14);
                doc.save().roundedRect(x, y, anchoFoto, altoFoto, 4).fillAndStroke('#FFFFFF', DISENO.colorBorde).restore();
                try {
                    doc.image(fotos[i + j], x + 4, y + 4, { fit: [anchoFoto - 8, altoFoto - 8], align: 'center', valign: 'center' });
                } catch (error) {
                    doc.fontSize(9).fillColor('#B00020').text('No se pudo incluir la imagen', x + 8, y + 8, { width: anchoFoto - 16 });
                }
                doc.fillColor(DISENO.colorTexto).font(fuentes.regular).fontSize(9).text(`Foto ${i + j + 1}`, x, y + altoFoto + 3, { width: anchoFoto, lineBreak: false });
            }
            doc.y = y + altoFoto + 22;
        }
    }

    // Firmas: una al lado de la otra, cada una en su recuadro
    const altoCaja = 125;
    titulo('Firmas', altoCaja + 50);
    const anchoCaja = (ANCHO_UTIL - 24) / 2;
    const yCajas = doc.y + 4;
    const pieTecnico = [`Técnico: ${tecnico || ''}`.trim(), matricula ? `Mat. ${matricula}` : ''].filter(Boolean).join(' · ');
    const firmas = [
        { buffer: bufferImagen(firmaTecnico), pie: pieTecnico },
        { buffer: bufferImagen(firmaCliente), pie: 'Firma y sello del cliente' },
    ];
    firmas.forEach((firma, indice) => {
        const x = MARGEN_X + indice * (anchoCaja + 24);
        doc.save().roundedRect(x, yCajas, anchoCaja, altoCaja, 5).fillAndStroke('#FFFFFF', DISENO.colorBorde).restore();
        if (firma.buffer) {
            try {
                doc.image(firma.buffer, x + 8, yCajas + 8, { fit: [anchoCaja - 16, altoCaja - 16], align: 'center', valign: 'center' });
            } catch (error) {
                doc.fontSize(9).fillColor('#B00020').text('No se pudo incluir la firma', x + 8, yCajas + 8, { width: anchoCaja - 16 });
            }
        } else {
            doc.fillColor('#9AA5A0').font(fuentes.regular).fontSize(10).text('Sin firma', x, yCajas + altoCaja / 2 - 6, { width: anchoCaja, align: 'center', lineBreak: false });
        }
        doc.fillColor(DISENO.colorTexto).font(fuentes.regular).fontSize(11).text(firma.pie, x, yCajas + altoCaja + 7, { width: anchoCaja, lineBreak: false });
    });
    doc.y = yCajas + altoCaja + 28;

    // Anexos: cada planilla de Excel completada, en su hoja, igual que el original.
    const planillas = completados.filter((f) => f.definicion.tipo === 'excel' && (f.contestadas || 0) > 0);
    if (planillas.length) {
        enAnexo = true;
        for (const formulario of planillas) dibujarPlanillaExcel(doc, formulario, { cliente, fin, fuentes });
    }

    doc.end();
    return new Promise((resolve, reject) => {
        archivo.on('finish', resolve);
        archivo.on('error', reject);
    });
}

module.exports = { crearInforme, textoEncabezado };
