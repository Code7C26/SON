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
    return fecha.toLocaleString('es-AR', { timeZone: 'America/Argentina/Buenos_Aires' });
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

function crearInforme({ destino, cliente, tecnico, direccion, comentarios, latitud, longitud, firmaTecnico, firmaCliente, evidencias, checklist, inicio, fin }) {
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
    doc.on('pageAdded', () => {
        hojas += 1;
        dibujarHoja(doc, hojas, fuentes, hayFuentes);
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

    // Tareas
    titulo('Tareas', 40);
    const items = Array.isArray(checklist) ? checklist : [];
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

    // Comentarios
    titulo('Comentarios');
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
    const firmas = [
        { buffer: bufferImagen(firmaTecnico), pie: `Técnico: ${tecnico || ''}`.trim() },
        { buffer: bufferImagen(firmaCliente), pie: 'Cliente' },
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

    doc.end();
    return new Promise((resolve, reject) => {
        archivo.on('finish', resolve);
        archivo.on('error', reject);
    });
}

module.exports = { crearInforme };
