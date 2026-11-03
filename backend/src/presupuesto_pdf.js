// PDF del presupuesto para el cliente, con el formato del formulario de la empresa (R 7.2 - 01/A):
// membrete con logo, datos del cliente, ítems con importe, condiciones, observaciones, datos
// administrativos y firma. Si algún ítem tiene "alcance", se agregan hojas con ese detalle.
const PDFDocument = require('pdfkit');
const fs = require('fs');
const path = require('path');

const CARPETA_ASSETS = path.join(__dirname, '..', 'assets');
const RUTA_LOGO = path.join(CARPETA_ASSETS, 'pdf', 'logo.png');
// Imagen de la firma (PNG con fondo transparente). Si no está, se deja el espacio en blanco para firmar a mano.
const RUTA_FIRMA = path.join(CARPETA_ASSETS, 'pdf', 'firma_presupuestos.png');
const FUENTES = {
    regular: path.join(CARPETA_ASSETS, 'fonts', 'BwGradualDEMO-Regular.otf'),
    media: path.join(CARPETA_ASSETS, 'fonts', 'BwGradualDEMO-Medium.otf'),
    negrita: path.join(CARPETA_ASSETS, 'fonts', 'BwGradualDEMO-Bold.otf'),
};

// Colores del formulario (azul con celdas de rótulo celestes).
const COLOR = {
    texto: '#1E2A3A',
    rotulo: '#3A4D6B',
    linea: '#5C8DC6',
    fondoRotulo: '#DCE7F4',
    fondoTitulo: '#C6D9EE',
    suave: '#6B7A8F',
};

const ANCHO = 595.28;
const ALTO = 841.89;
const MARGEN_X = 36;
const MARGEN_SUPERIOR = 100; // lugar del membrete
const MARGEN_INFERIOR = 40;
const ANCHO_UTIL = ANCHO - MARGEN_X * 2;
const LIMITE_Y = ALTO - MARGEN_INFERIOR;

// 503792 -> "503.792" (siempre con punto cada tres cifras, también en números de 4 cifras)
function numeroConPuntos(valor) {
    const entero = Math.round(Number(valor) || 0);
    return String(Math.abs(entero)).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}
const pesos = (valor) => `$ ${numeroConPuntos(valor)}`;

// "2026-09-21" -> "21/09/2026"
function fechaCorta(texto) {
    const m = String(texto || '').match(/^(\d{4})-(\d{2})-(\d{2})/);
    return m ? `${m[3]}/${m[2]}/${m[1]}` : '';
}

function crearPresupuestoPdf(destino, datos) {
    const hayFuentes = Object.values(FUENTES).every((ruta) => fs.existsSync(ruta));
    const doc = new PDFDocument({
        size: 'A4',
        margins: { top: MARGEN_SUPERIOR, bottom: 0, left: MARGEN_X, right: MARGEN_X },
        bufferPages: true,
        info: { Title: `Presupuesto ${datos.etiqueta}`, Author: (datos.config.empresa && datos.config.empresa.razon_social) || 'Sima' },
    });
    const fuentes = hayFuentes
        ? (doc.registerFont('regular', FUENTES.regular), doc.registerFont('media', FUENTES.media), doc.registerFont('negrita', FUENTES.negrita), { regular: 'regular', media: 'media', negrita: 'negrita' })
        : { regular: 'Helvetica', media: 'Helvetica-Bold', negrita: 'Helvetica-Bold' };

    const terminado = new Promise((resolve, reject) => {
        destino.on('finish', resolve);
        destino.on('error', reject);
        doc.on('error', reject);
    });
    doc.pipe(destino);

    const empresa = datos.config.empresa || {};
    const textos = datos.config.textos || {};
    const cliente = datos.cliente || {};

    // --- Herramientas de dibujo ---
    function caja(x, y, ancho, alto, relleno) {
        doc.save();
        if (relleno) doc.rect(x, y, ancho, alto).fillAndStroke(relleno, COLOR.linea);
        else doc.rect(x, y, ancho, alto).stroke(COLOR.linea);
        doc.restore();
    }

    function alto(texto, ancho, fuente, tamano) {
        doc.font(fuente).fontSize(tamano);
        return doc.heightOfString(String(texto || ' '), { width: ancho, lineGap: 1.5 });
    }

    // Dibuja una celda con texto (centrado vertical por defecto).
    function celda(x, y, ancho, altoCelda, texto, { relleno, fuente = fuentes.regular, tamano = 9, color = COLOR.texto, alineacion = 'left', rellenoX = 5, arriba = false } = {}) {
        caja(x, y, ancho, altoCelda, relleno);
        const contenido = String(texto ?? '');
        if (!contenido) return;
        const anchoTexto = ancho - rellenoX * 2;
        const altoTextoCelda = alto(contenido, anchoTexto, fuente, tamano);
        const desplazamiento = arriba ? 4 : Math.max((altoCelda - altoTextoCelda) / 2, 2);
        doc.fillColor(color).font(fuente).fontSize(tamano).text(contenido, x + rellenoX, y + desplazamiento, { width: anchoTexto, align: alineacion, lineGap: 1.5 });
    }

    function dibujarMembrete(numeroDePagina, totalDePaginas) {
        const x = MARGEN_X;
        const y = 28;
        const alturaMembrete = 56;
        const anchoCajita = 100;
        caja(x, y, ANCHO_UTIL, alturaMembrete);
        // Logo
        if (fs.existsSync(RUTA_LOGO)) doc.image(RUTA_LOGO, x + 8, y + 7, { fit: [150, 42] });
        else doc.fillColor(COLOR.texto).font(fuentes.negrita).fontSize(20).text('SIMA', x + 12, y + 18, { lineBreak: false });
        // Título
        doc.fillColor(COLOR.rotulo).font(fuentes.media).fontSize(17).text('P R E S U P U E S T O', x + 150, y + 19, { width: ANCHO_UTIL - 150 - anchoCajita, align: 'center', lineBreak: false, characterSpacing: 1 });
        // Cajita de la derecha: código del formulario, número y hoja
        const xc = x + ANCHO_UTIL - anchoCajita;
        const filas = [textos.codigo_formulario || '', datos.etiqueta, `Hoja ${numeroDePagina} de ${totalDePaginas}`];
        const altoFila = alturaMembrete / 3;
        filas.forEach((texto, i) => {
            celda(xc, y + altoFila * i, anchoCajita, altoFila, texto, { fuente: i === 1 ? fuentes.negrita : fuentes.media, tamano: i === 1 ? 10 : 8, alineacion: 'center', color: COLOR.rotulo });
        });
    }

    function paginaNueva() {
        doc.addPage();
        return MARGEN_SUPERIOR;
    }

    // --- Datos del cliente ---
    let y = MARGEN_SUPERIOR - 4;
    const COL = [66, 196, 66, ANCHO_UTIL - 66 - 196 - 66];
    const filasCliente = [
        ['Cliente', cliente.razonSocial, 'Nº', datos.etiqueta],
        ['Domicilio', cliente.direccion, 'Fecha', fechaCorta(datos.fecha)],
        ['Teléfono', cliente.telefono, 'Localidad', cliente.localidad],
        ['E-Mail', cliente.email, 'Provincia', cliente.provincia],
        ['Atención', cliente.atencion, 'CUIT', cliente.cuit],
    ];
    for (const [rotulo1, valor1, rotulo2, valor2] of filasCliente) {
        const altoFila = Math.max(21, alto(valor1, COL[1] - 10, fuentes.regular, 9.5) + 8, alto(valor2, COL[3] - 10, fuentes.regular, 9.5) + 8);
        let x = MARGEN_X;
        celda(x, y, COL[0], altoFila, rotulo1, { relleno: COLOR.fondoRotulo, fuente: fuentes.media, tamano: 8.5, color: COLOR.rotulo });
        x += COL[0];
        celda(x, y, COL[1], altoFila, valor1, { tamano: 9.5, fuente: rotulo1 === 'Cliente' ? fuentes.negrita : fuentes.regular });
        x += COL[1];
        celda(x, y, COL[2], altoFila, rotulo2, { relleno: COLOR.fondoRotulo, fuente: fuentes.media, tamano: 8.5, color: COLOR.rotulo });
        x += COL[2];
        celda(x, y, COL[3], altoFila, valor2, { tamano: 9.5, fuente: rotulo2 === 'Nº' ? fuentes.negrita : fuentes.regular });
        y += altoFila;
    }
    y += 12;

    // --- Ítems ---
    const hayCantidades = datos.items.some((item) => Number(item.cantidad) !== 1);
    const columnas = hayCantidades
        ? { numero: 40, cantidad: 44, unitario: 92, importe: 92 }
        : { numero: 46, cantidad: 0, unitario: 108, importe: 0 };
    columnas.detalle = ANCHO_UTIL - columnas.numero - columnas.cantidad - columnas.unitario - columnas.importe;

    function encabezadoDeItems(posicionY) {
        const altoEncabezado = 28;
        let x = MARGEN_X;
        const estilo = { relleno: COLOR.fondoTitulo, fuente: fuentes.negrita, tamano: 8.5, alineacion: 'center', color: COLOR.rotulo };
        celda(x, posicionY, columnas.numero, altoEncabezado, 'Nº de ítem', estilo);
        x += columnas.numero;
        celda(x, posicionY, columnas.detalle, altoEncabezado, 'DETALLE', estilo);
        x += columnas.detalle;
        if (hayCantidades) {
            celda(x, posicionY, columnas.cantidad, altoEncabezado, 'CANT.', estilo);
            x += columnas.cantidad;
        }
        celda(x, posicionY, columnas.unitario, altoEncabezado, 'IMPORTE UNITARIO', estilo);
        x += columnas.unitario;
        if (hayCantidades) celda(x, posicionY, columnas.importe, altoEncabezado, 'IMPORTE', estilo);
        return posicionY + altoEncabezado;
    }

    y = encabezadoDeItems(y);
    datos.items.forEach((item, indice) => {
        const linea = datos.calculo.lineas[indice];
        const descripcion = item.alcance && !/alcance adjunto/i.test(item.descripcion) ? `${item.descripcion}\nVer alcance adjunto.` : item.descripcion;
        const anchoDetalle = columnas.detalle - 12;
        const altoDescripcion = alto(descripcion, anchoDetalle, fuentes.regular, 9.5);
        const altoFila = Math.max(54, altoDescripcion + 16);
        if (y + altoFila > LIMITE_Y - 20) {
            paginaNueva();
            y = encabezadoDeItems(MARGEN_SUPERIOR - 4);
        }
        let x = MARGEN_X;
        celda(x, y, columnas.numero, altoFila, String(indice + 1), { fuente: fuentes.media, tamano: 10, alineacion: 'center', arriba: false });
        x += columnas.numero;
        caja(x, y, columnas.detalle, altoFila);
        doc.fillColor(COLOR.texto).font(fuentes.regular).fontSize(9.5).text(descripcion, x + 6, y + 8, { width: anchoDetalle, lineGap: 1.5 });
        x += columnas.detalle;
        if (hayCantidades) {
            celda(x, y, columnas.cantidad, altoFila, String(Number(item.cantidad)).replace('.', ','), { alineacion: 'center', tamano: 10 });
            x += columnas.cantidad;
        }
        // Importe (ya con la bonificación) y cómo se cobra. Con columna de cantidades, "cómo se cobra" va
        // debajo del importe de la línea; sin ella, debajo del único importe.
        const sinCosto = linea.neto === 0;
        let aclaracion = '';
        if (item.periodicidad === 'mensual') aclaracion = 'por mes';
        else if (item.prorratearMeses) aclaracion = `en ${item.prorratearMeses} cuotas de $${numeroConPuntos(linea.mensual)}`;
        else aclaracion = 'pago único';
        const celdaDeImporte = (posX, ancho, textoPrecio, conAclaracion) => {
            caja(posX, y, ancho, altoFila);
            const altoPrecio = alto(textoPrecio, ancho - 8, fuentes.negrita, 11);
            const altoAclaracion = conAclaracion ? alto(aclaracion, ancho - 8, fuentes.regular, 7.5) + 2 : 0;
            const inicioPrecio = y + Math.max((altoFila - altoPrecio - altoAclaracion) / 2, 4);
            doc.fillColor(COLOR.texto).font(fuentes.negrita).fontSize(11).text(textoPrecio, posX + 4, inicioPrecio, { width: ancho - 8, align: 'center' });
            if (conAclaracion) doc.fillColor(COLOR.suave).font(fuentes.regular).fontSize(7.5).text(aclaracion, posX + 4, inicioPrecio + altoPrecio + 2, { width: ancho - 8, align: 'center' });
        };
        if (hayCantidades) {
            celdaDeImporte(x, columnas.unitario, linea.precioNetoUnitario === 0 ? 'Bonificado' : pesos(linea.precioNetoUnitario), false);
            x += columnas.unitario;
            celdaDeImporte(x, columnas.importe, sinCosto ? 'Bonificado' : pesos(linea.neto), !sinCosto);
        } else {
            celdaDeImporte(x, columnas.unitario, sinCosto ? 'Bonificado' : pesos(linea.precioNetoUnitario), !sinCosto);
        }
        y += altoFila;
    });

    // Totales (si hay más de un ítem) y aclaración del IVA
    const variosItems = datos.items.length > 1;
    const totales = [];
    if (variosItems && datos.calculo.totalMensual > 0) totales.push(['TOTAL MENSUAL', datos.calculo.totalMensual]);
    if (variosItems && datos.calculo.totalUnico > 0) totales.push(['TOTAL PAGO ÚNICO', datos.calculo.totalUnico]);
    const anchoTotales = columnas.cantidad + columnas.unitario + columnas.importe;
    const xTotales = MARGEN_X + ANCHO_UTIL - anchoTotales;
    const apilado = anchoTotales < 150; // sin columnas de cantidad e importe: el rótulo va arriba y el monto abajo
    const estiloTotal = { relleno: COLOR.fondoRotulo, fuente: fuentes.negrita, tamano: 8, alineacion: 'center', color: COLOR.rotulo };
    for (const [rotulo, valor] of totales) {
        const alturaTotal = apilado ? 40 : 22;
        if (y + alturaTotal > LIMITE_Y - 20) y = paginaNueva() - 4;
        if (apilado) {
            celda(xTotales, y, anchoTotales, 18, rotulo, estiloTotal);
            celda(xTotales, y + 18, anchoTotales, 22, pesos(valor), { fuente: fuentes.negrita, tamano: 10.5, alineacion: 'center' });
        } else {
            celda(xTotales, y, 120, 22, rotulo, estiloTotal);
            celda(xTotales + 120, y, anchoTotales - 120, 22, pesos(valor), { fuente: fuentes.negrita, tamano: 10.5, alineacion: 'center' });
        }
        y += alturaTotal;
    }
    doc.fillColor(COLOR.texto).font(fuentes.negrita).fontSize(8.5).text('(El precio indicado no incluye IVA)', MARGEN_X, y + 6, { width: ANCHO_UTIL, align: 'right', lineBreak: false });
    y += 28;

    // --- Condiciones y observaciones ---
    const anchoCondiciones = 266;
    const anchoObservaciones = ANCHO_UTIL - anchoCondiciones;
    const anchoRotuloCond = 84;
    const filasCondiciones = [
        ['Forma de pago', datos.formaPago || ''],
        ['Plazo Entrega', datos.plazoEntrega || ''],
        ['Validez de la Oferta', [datos.validez, datos.referencia].filter(Boolean).join('\n')],
    ];
    const altosCondiciones = filasCondiciones.map(([, valor]) => Math.max(24, alto(valor, anchoCondiciones - anchoRotuloCond - 10, fuentes.regular, 8.5) + 10));
    const altoBloqueCondiciones = 22 + altosCondiciones.reduce((a, b) => a + b, 0);
    const textoObservaciones = datos.observaciones || '';
    const altoObservaciones = Math.max(altoBloqueCondiciones, 22 + alto(textoObservaciones, anchoObservaciones - 16, fuentes.regular, 9) + 14);

    // Si no entran las condiciones, los datos administrativos y la firma, siguen en otra hoja.
    const altoDatosAdministrativos = 22 + 22 + 4 * 24;
    const altoNecesario = altoObservaciones + 14 + altoDatosAdministrativos + 14 + 110;
    if (y + altoNecesario > LIMITE_Y) y = paginaNueva();

    const estiloTitulo = { relleno: COLOR.fondoTitulo, fuente: fuentes.negrita, tamano: 9, alineacion: 'center', color: COLOR.rotulo };
    celda(MARGEN_X, y, anchoCondiciones, 22, 'CONDICIONES', estiloTitulo);
    celda(MARGEN_X + anchoCondiciones, y, anchoObservaciones, 22, 'OBSERVACIONES', estiloTitulo);
    let yCondicion = y + 22;
    filasCondiciones.forEach(([rotulo, valor], i) => {
        celda(MARGEN_X, yCondicion, anchoRotuloCond, altosCondiciones[i], rotulo, { relleno: COLOR.fondoRotulo, fuente: fuentes.media, tamano: 8.5, color: COLOR.rotulo });
        celda(MARGEN_X + anchoRotuloCond, yCondicion, anchoCondiciones - anchoRotuloCond, altosCondiciones[i], valor, { tamano: 8.5 });
        yCondicion += altosCondiciones[i];
    });
    // Para que las dos columnas terminen a la misma altura
    const sobrante = altoObservaciones - altoBloqueCondiciones;
    if (sobrante > 0.5) caja(MARGEN_X, yCondicion, anchoCondiciones, sobrante);
    caja(MARGEN_X + anchoCondiciones, y + 22, anchoObservaciones, altoObservaciones - 22);
    if (textoObservaciones) doc.fillColor(COLOR.texto).font(fuentes.regular).fontSize(9).text(textoObservaciones, MARGEN_X + anchoCondiciones + 8, y + 22 + 8, { width: anchoObservaciones - 16, lineGap: 1.5 });
    y += altoObservaciones;

    // --- Datos administrativos ---
    celda(MARGEN_X, y, ANCHO_UTIL, 22, 'DATOS ADMINISTRATIVOS', estiloTitulo);
    y += 22;
    celda(MARGEN_X, y, ANCHO_UTIL, 22, empresa.titulo || '', { ...estiloTitulo, fuente: fuentes.media });
    y += 22;
    const filasAdmin = [
        ['Razón social', empresa.razon_social, 'C.U.I.T.', empresa.cuit],
        ['Dirección', empresa.direccion, 'Teléfonos', empresa.telefonos],
        ['IVA', empresa.iva, 'Celular', empresa.celular],
        ['E-Mail', empresa.email, 'Pág. Web', empresa.web],
    ];
    const COL_ADMIN = [74, 188, 74, ANCHO_UTIL - 74 - 188 - 74];
    for (const [r1, v1, r2, v2] of filasAdmin) {
        const altoFila = Math.max(22, alto(v1, COL_ADMIN[1] - 10, fuentes.regular, 8.5) + 10, alto(v2, COL_ADMIN[3] - 10, fuentes.regular, 8.5) + 10);
        let x = MARGEN_X;
        celda(x, y, COL_ADMIN[0], altoFila, r1, { relleno: COLOR.fondoRotulo, fuente: fuentes.media, tamano: 8.5, color: COLOR.rotulo });
        x += COL_ADMIN[0];
        celda(x, y, COL_ADMIN[1], altoFila, v1, { tamano: 8.5 });
        x += COL_ADMIN[1];
        celda(x, y, COL_ADMIN[2], altoFila, r2, { relleno: COLOR.fondoRotulo, fuente: fuentes.media, tamano: 8.5, color: COLOR.rotulo });
        x += COL_ADMIN[2];
        celda(x, y, COL_ADMIN[3], altoFila, v2, { tamano: 8.5 });
        y += altoFila;
    }

    // --- Firma ---
    y += 14;
    const firma = datos.config.firma || {};
    const centroX = ANCHO / 2;
    if (fs.existsSync(RUTA_FIRMA)) doc.image(RUTA_FIRMA, centroX - 55, y, { fit: [110, 46] });
    y += 50;
    doc.fillColor(COLOR.texto).font(fuentes.negrita).fontSize(9.5).text(firma.nombre || '', 0, y, { width: ANCHO, align: 'center', lineBreak: false });
    y += 13;
    doc.fillColor(COLOR.texto).font(fuentes.regular).fontSize(9).text(firma.cargo || '', 0, y, { width: ANCHO, align: 'center', lineBreak: false });
    y += 12;
    doc.text(firma.empresa || '', 0, y, { width: ANCHO, align: 'center', lineBreak: false });

    // --- Hojas con el alcance de cada servicio ---
    const conAlcance = datos.items.map((item, indice) => ({ item, numero: indice + 1 })).filter(({ item }) => item.alcance);
    if (conAlcance.length) {
        y = paginaNueva();
        celda(MARGEN_X, y - 4, ANCHO_UTIL, 24, 'ALCANCE DEL SERVICIO', estiloTitulo);
        y += 30;
        for (const { item, numero } of conAlcance) {
            const titulo = `Ítem ${numero}: ${String(item.descripcion).split('\n')[0]}`;
            const altoTitulo = alto(titulo, ANCHO_UTIL - 12, fuentes.negrita, 10);
            if (y + altoTitulo + 40 > LIMITE_Y) y = paginaNueva();
            doc.fillColor(COLOR.rotulo).font(fuentes.negrita).fontSize(10).text(titulo, MARGEN_X + 6, y, { width: ANCHO_UTIL - 12, lineGap: 1.5 });
            y += altoTitulo + 6;
            // El alcance se escribe párrafo por párrafo para poder cortar entre hojas sin perder el lugar.
            for (const parrafo of String(item.alcance).split(/\n+/)) {
                const altoParrafo = alto(parrafo, ANCHO_UTIL - 12, fuentes.regular, 9.5);
                if (y + altoParrafo > LIMITE_Y) y = paginaNueva();
                doc.fillColor(COLOR.texto).font(fuentes.regular).fontSize(9.5).text(parrafo, MARGEN_X + 6, y, { width: ANCHO_UTIL - 12, lineGap: 1.5 });
                y += altoParrafo + 5;
            }
            y += 10;
        }
    }

    // --- Membrete en todas las hojas (ahora que se sabe cuántas son) ---
    const rango = doc.bufferedPageRange();
    for (let i = 0; i < rango.count; i++) {
        doc.switchToPage(rango.start + i);
        dibujarMembrete(i + 1, rango.count);
    }
    doc.end();
    return terminado;
}

module.exports = { crearPresupuestoPdf, numeroConPuntos, pesos };
