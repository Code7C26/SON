// Lector mínimo de planillas de Excel (.xls viejo y .xlsx), sin dependencias externas.
// Lee lo necesario para mostrar el formulario igual que en Excel: el texto de cada celda, las celdas
// combinadas, los bordes, la alineación, la negrita, el texto girado, el ancho de las columnas y el
// alto de las filas. No lee colores, imágenes ni fórmulas complejas.
//
// Devuelve: { hojas: [hoja] } y cada hoja tiene:
//   celdas: Map('fila,columna' -> texto)      estilos: Map('fila,columna' -> estilo)
//   combinadas: [{ f1, c1, f2, c2 }]           anchos: Map(columna -> ancho en caracteres)
//   altos: Map(fila -> alto en puntos)         ocultas: { filas: Set, columnas: Set }
//   anchoBase (caracteres), altoBase (puntos), filas, columnas
// Un estilo es { b: [izq, der, arriba, abajo] (0 = sin borde), h: 'l'|'c'|'r'|'', v: 't'|'c'|'b',
//   w: ajusta texto, r: giro en grados (90, -90, 255 = apilado), n: negrita, z: tamaño en puntos }.
// Las filas y columnas empiezan en 0.
const zlib = require('zlib');

const LIMITE_CELDAS = 20000;

function nuevaHoja(nombre) {
    return {
        nombre, celdas: new Map(), estilos: new Map(), combinadas: [], anchos: new Map(), altos: new Map(),
        ocultas: { filas: new Set(), columnas: new Set() }, anchoBase: 8.43, altoBase: 12.75, filas: 0, columnas: 0,
    };
}

function extender(hoja, fila, columna) {
    hoja.filas = Math.max(hoja.filas, fila + 1);
    hoja.columnas = Math.max(hoja.columnas, columna + 1);
}

function ponerCelda(hoja, fila, columna, valor) {
    if (valor === null || valor === undefined) return;
    const texto = String(valor).replace(/\r\n?/g, '\n').trim();
    if (!texto || hoja.celdas.size >= LIMITE_CELDAS) return;
    hoja.celdas.set(`${fila},${columna}`, texto);
    extender(hoja, fila, columna);
}

function tieneBorde(estilo) {
    return Boolean(estilo && estilo.b && estilo.b.some((lado) => lado > 0));
}

function ponerEstilo(hoja, fila, columna, estilo) {
    if (!estilo || hoja.estilos.size >= LIMITE_CELDAS) return;
    hoja.estilos.set(`${fila},${columna}`, estilo);
    if (tieneBorde(estilo)) extender(hoja, fila, columna);
}

function numeroComoTexto(numero) {
    if (!Number.isFinite(numero)) return '';
    return Number.isInteger(numero) ? String(numero) : String(Math.round(numero * 1e6) / 1e6);
}

// =====================================================================
// .xls (BIFF8 dentro de un contenedor OLE / "Compound File")
// =====================================================================
const FIN_DE_CADENA = 0xfffffffe;
const LIBRE = 0xffffffff;

function leerContenedor(buffer) {
    if (buffer.length < 512 || buffer.readUInt32LE(0) !== 0xe011cfd0 || buffer.readUInt32LE(4) !== 0xe11ab1a1) {
        throw new Error('No es un archivo de Excel válido');
    }
    const tamSector = 1 << buffer.readUInt16LE(0x1e);
    const tamMini = 1 << buffer.readUInt16LE(0x20);
    const primerDirectorio = buffer.readUInt32LE(0x30);
    const corteMini = buffer.readUInt32LE(0x38);
    const primerMiniFat = buffer.readUInt32LE(0x3c);
    let sectorDifat = buffer.readUInt32LE(0x44);
    const cantidadDifat = buffer.readUInt32LE(0x48);
    const sector = (n) => {
        const inicio = (n + 1) * tamSector;
        if (inicio + tamSector > buffer.length) throw new Error('Archivo de Excel incompleto');
        return buffer.subarray(inicio, inicio + tamSector);
    };

    // Sectores que forman la tabla de asignación (FAT).
    const sectoresFat = [];
    for (let i = 0; i < 109; i++) {
        const valor = buffer.readUInt32LE(0x4c + i * 4);
        if (valor !== LIBRE && valor !== FIN_DE_CADENA) sectoresFat.push(valor);
    }
    for (let i = 0; i < cantidadDifat && sectorDifat !== FIN_DE_CADENA && sectorDifat !== LIBRE; i++) {
        const datos = sector(sectorDifat);
        for (let j = 0; j < tamSector / 4 - 1; j++) {
            const valor = datos.readUInt32LE(j * 4);
            if (valor !== LIBRE && valor !== FIN_DE_CADENA) sectoresFat.push(valor);
        }
        sectorDifat = datos.readUInt32LE(tamSector - 4);
    }
    const fat = [];
    for (const n of sectoresFat) {
        const datos = sector(n);
        for (let j = 0; j < tamSector / 4; j++) fat.push(datos.readUInt32LE(j * 4));
    }
    const cadena = (inicio, tabla, leer, maximo) => {
        const partes = [];
        const vistos = new Set();
        let actual = inicio;
        while (actual !== FIN_DE_CADENA && actual !== LIBRE && actual < tabla.length && !vistos.has(actual) && partes.length < maximo) {
            vistos.add(actual);
            partes.push(leer(actual));
            actual = tabla[actual];
        }
        return Buffer.concat(partes);
    };
    const flujo = (inicio, tamano) => cadena(inicio, fat, sector, Math.ceil(tamano / tamSector) + 1).subarray(0, tamano);

    // Directorio: busca el libro ("Workbook" o, en archivos muy viejos, "Book").
    const directorio = cadena(primerDirectorio, fat, sector, 10000);
    let raiz = null;
    let libro = null;
    for (let i = 0; i + 128 <= directorio.length; i += 128) {
        const largo = directorio.readUInt16LE(i + 0x40);
        const nombre = directorio.toString('utf16le', i, i + Math.max(0, largo - 2));
        const tipo = directorio[i + 0x42];
        const entrada = { inicio: directorio.readUInt32LE(i + 0x74), tamano: directorio.readUInt32LE(i + 0x78) };
        if (tipo === 5) raiz = entrada;
        if (tipo === 2 && (nombre === 'Workbook' || nombre === 'Book')) libro = entrada;
    }
    if (!libro) throw new Error('El archivo no tiene una hoja de Excel');
    if (libro.tamano >= corteMini || !raiz) return flujo(libro.inicio, libro.tamano);

    // Libros chicos: viven en el "mini flujo".
    const miniFatDatos = primerMiniFat === FIN_DE_CADENA ? Buffer.alloc(0) : cadena(primerMiniFat, fat, sector, 10000);
    const miniFat = [];
    for (let j = 0; j + 4 <= miniFatDatos.length; j += 4) miniFat.push(miniFatDatos.readUInt32LE(j));
    const miniFlujo = flujo(raiz.inicio, raiz.tamano);
    const miniSector = (n) => miniFlujo.subarray(n * tamMini, (n + 1) * tamMini);
    return cadena(libro.inicio, miniFat, miniSector, Math.ceil(libro.tamano / tamMini) + 1).subarray(0, libro.tamano);
}

// Lee bytes de un registro y sus CONTINUE como si fueran uno solo. Los textos que se cortan entre
// registros llevan un byte nuevo de opciones al principio del siguiente (así es el formato).
class LectorPartido {
    constructor(partes) {
        this.partes = partes.filter((parte) => parte.length);
        this.indice = 0;
        this.pos = 0;
    }

    get terminado() {
        return this.indice >= this.partes.length;
    }

    avanzar() {
        while (!this.terminado && this.pos >= this.partes[this.indice].length) {
            this.indice += 1;
            this.pos = 0;
        }
    }

    byte() {
        this.avanzar();
        if (this.terminado) throw new Error('Fin inesperado');
        return this.partes[this.indice][this.pos++];
    }

    u16() { return this.byte() | (this.byte() << 8); }
    u32() { return (this.u16() | (this.u16() << 16)) >>> 0; }

    saltar(n) {
        let faltan = n;
        while (faltan > 0) {
            this.avanzar();
            if (this.terminado) return;
            const hay = Math.min(faltan, this.partes[this.indice].length - this.pos);
            this.pos += hay;
            faltan -= hay;
        }
    }

    caracteres(cantidad, anchoInicial) {
        let ancho = anchoInicial;
        let texto = '';
        let faltan = cantidad;
        while (faltan > 0) {
            if (this.pos >= this.partes[this.indice].length) {
                this.indice += 1;
                this.pos = 0;
                if (this.terminado) break;
                ancho = this.partes[this.indice][this.pos++] & 1; // byte de opciones del CONTINUE
            }
            const parte = this.partes[this.indice];
            const bytesPorChar = ancho ? 2 : 1;
            const hay = Math.min(faltan, Math.floor((parte.length - this.pos) / bytesPorChar));
            if (hay <= 0) { this.pos = parte.length; continue; }
            texto += ancho ? parte.toString('utf16le', this.pos, this.pos + hay * 2) : parte.toString('latin1', this.pos, this.pos + hay);
            this.pos += hay * bytesPorChar;
            faltan -= hay;
        }
        return texto;
    }

    // Texto Unicode de Excel (XLUnicodeRichExtendedString).
    texto() {
        const cantidad = this.u16();
        const opciones = this.byte();
        const rico = opciones & 0x08 ? this.u16() : 0;
        const extendido = opciones & 0x04 ? this.u32() : 0;
        const valor = this.caracteres(cantidad, opciones & 1);
        this.saltar(rico * 4 + extendido);
        return valor;
    }
}

function textoCorto(datos, desde, largoEn8bits = false) {
    const cantidad = largoEn8bits ? datos[desde] : datos.readUInt16LE(desde);
    let pos = desde + (largoEn8bits ? 1 : 2);
    const ancho = datos[pos] & 1;
    pos += 1;
    return ancho ? datos.toString('utf16le', pos, pos + cantidad * 2) : datos.toString('latin1', pos, pos + cantidad);
}

function rk(valor) {
    let numero;
    if (valor & 0x02) {
        numero = valor >> 2;
    } else {
        const temporal = Buffer.alloc(8);
        temporal.writeUInt32LE(valor & 0xfffffffc, 4);
        numero = temporal.readDoubleLE(0);
    }
    return valor & 0x01 ? numero / 100 : numero;
}

const HORIZONTAL_XLS = { 1: 'l', 2: 'c', 3: 'r', 6: 'c' };
const VERTICAL_XLS = { 0: 't', 1: 'c', 2: 'b' };

function giroXls(trot) {
    if (trot === 255) return 255;
    if (trot > 0 && trot <= 90) return trot; // en sentido antihorario
    if (trot > 90 && trot <= 180) return -(trot - 90); // en sentido horario
    return 0;
}

function leerXls(buffer) {
    const datos = leerContenedor(buffer);
    const registros = [];
    for (let pos = 0; pos + 4 <= datos.length;) {
        const tipo = datos.readUInt16LE(pos);
        const largo = datos.readUInt16LE(pos + 2);
        registros.push({ tipo, inicio: pos, datos: datos.subarray(pos + 4, pos + 4 + largo) });
        pos += 4 + largo;
    }
    const continuaciones = (indice) => {
        const partes = [registros[indice].datos];
        for (let j = indice + 1; j < registros.length && registros[j].tipo === 0x003c; j++) partes.push(registros[j].datos);
        return partes;
    };

    // Primero lo global: textos compartidos, fuentes, formatos de celda (XF) y la lista de hojas.
    let textos = [];
    const fuentes = [];
    const formatos = [];
    const hojasDeclaradas = [];
    for (let i = 0; i < registros.length; i++) {
        const { tipo, datos: d } = registros[i];
        if (tipo === 0x00fc) {
            const lector = new LectorPartido(continuaciones(i));
            lector.u32();
            const unicos = lector.u32();
            textos = [];
            try {
                for (let j = 0; j < unicos && !lector.terminado; j++) textos.push(lector.texto());
            } catch (_) { /* texto cortado: se usa lo que se pudo leer */ }
        } else if (tipo === 0x0085) {
            hojasDeclaradas.push({ posicion: d.readUInt32LE(0), tipo: d[5], nombre: textoCorto(d, 6, true) });
        } else if (tipo === 0x0031 && d.length >= 8) {
            fuentes.push({ z: d.readUInt16LE(0) / 20, n: d.readUInt16LE(6) >= 700 });
        } else if (tipo === 0x00e0 && d.length >= 14) {
            const indiceFuente = d.readUInt16LE(0);
            const fuente = fuentes[indiceFuente >= 4 ? indiceFuente - 1 : indiceFuente] || { z: 10, n: false };
            const alineacion = d[6];
            const bordes = d.readUInt16LE(10);
            formatos.push({
                b: [bordes & 0xf, (bordes >> 4) & 0xf, (bordes >> 8) & 0xf, (bordes >> 12) & 0xf],
                h: HORIZONTAL_XLS[alineacion & 7] || '',
                v: VERTICAL_XLS[(alineacion >> 4) & 7] || 'b',
                w: Boolean(alineacion & 0x08),
                r: giroXls(d[7]),
                n: fuente.n,
                z: fuente.z,
            });
        }
    }
    const estiloDe = (indice) => formatos[indice] || null;

    const hojas = [];
    for (const declarada of hojasDeclaradas) {
        if (declarada.tipo !== 0) continue; // solo hojas de cálculo (no gráficos ni macros)
        const hoja = nuevaHoja(declarada.nombre);
        let i = registros.findIndex((registro) => registro.inicio === declarada.posicion);
        if (i < 0) continue;
        let formulaPendiente = null;
        for (i += 1; i < registros.length && registros[i].tipo !== 0x000a; i++) {
            const { tipo, datos: d } = registros[i];
            try {
                // Casi todos los registros de celda empiezan igual: fila, columna, formato.
                const celdaConFormato = [0x00fd, 0x0204, 0x0203, 0x027e, 0x0006, 0x0201, 0x0205].includes(tipo) && d.length >= 6;
                if (celdaConFormato) ponerEstilo(hoja, d.readUInt16LE(0), d.readUInt16LE(2), estiloDe(d.readUInt16LE(4)));

                if (tipo === 0x00fd && d.length >= 10) {
                    ponerCelda(hoja, d.readUInt16LE(0), d.readUInt16LE(2), textos[d.readUInt32LE(6)]);
                } else if (tipo === 0x0204 && d.length >= 9) {
                    ponerCelda(hoja, d.readUInt16LE(0), d.readUInt16LE(2), textoCorto(d, 6));
                } else if (tipo === 0x0203 && d.length >= 14) {
                    ponerCelda(hoja, d.readUInt16LE(0), d.readUInt16LE(2), numeroComoTexto(d.readDoubleLE(6)));
                } else if (tipo === 0x027e && d.length >= 10) {
                    ponerCelda(hoja, d.readUInt16LE(0), d.readUInt16LE(2), numeroComoTexto(rk(d.readUInt32LE(6))));
                } else if (tipo === 0x00bd && d.length >= 6) {
                    const fila = d.readUInt16LE(0);
                    const primera = d.readUInt16LE(2);
                    const cantidad = (d.length - 6) / 6;
                    for (let k = 0; k < cantidad; k++) {
                        ponerEstilo(hoja, fila, primera + k, estiloDe(d.readUInt16LE(4 + k * 6)));
                        ponerCelda(hoja, fila, primera + k, numeroComoTexto(rk(d.readUInt32LE(4 + k * 6 + 2))));
                    }
                } else if (tipo === 0x00be && d.length >= 6) {
                    // Varias celdas vacías seguidas con formato (por ejemplo, los casilleros con borde).
                    const fila = d.readUInt16LE(0);
                    const primera = d.readUInt16LE(2);
                    const cantidad = (d.length - 6) / 2;
                    for (let k = 0; k < cantidad; k++) ponerEstilo(hoja, fila, primera + k, estiloDe(d.readUInt16LE(4 + k * 2)));
                } else if (tipo === 0x0006 && d.length >= 14) {
                    const fila = d.readUInt16LE(0);
                    const columna = d.readUInt16LE(2);
                    if (d.readUInt16LE(12) === 0xffff) {
                        if (d[6] === 0) formulaPendiente = { fila, columna };
                    } else {
                        ponerCelda(hoja, fila, columna, numeroComoTexto(d.readDoubleLE(6)));
                    }
                } else if (tipo === 0x0207 && formulaPendiente) {
                    ponerCelda(hoja, formulaPendiente.fila, formulaPendiente.columna, new LectorPartido(continuaciones(i)).texto());
                    formulaPendiente = null;
                } else if (tipo === 0x00e5 && d.length >= 2) {
                    const cantidad = d.readUInt16LE(0);
                    for (let k = 0; k < cantidad && 2 + k * 8 + 8 <= d.length; k++) {
                        const base = 2 + k * 8;
                        hoja.combinadas.push({ f1: d.readUInt16LE(base), f2: d.readUInt16LE(base + 2), c1: d.readUInt16LE(base + 4), c2: d.readUInt16LE(base + 6) });
                    }
                } else if (tipo === 0x007d && d.length >= 10) {
                    // Ancho de columnas (en 1/256 de carácter) y columnas ocultas.
                    for (let c = d.readUInt16LE(0); c <= Math.min(d.readUInt16LE(2), 255); c++) {
                        hoja.anchos.set(c, d.readUInt16LE(4) / 256);
                        if (d.readUInt16LE(8) & 1) hoja.ocultas.columnas.add(c);
                    }
                } else if (tipo === 0x0055 && d.length >= 2) {
                    hoja.anchoBase = d.readUInt16LE(0) + 0.43;
                } else if (tipo === 0x0099 && d.length >= 2) {
                    hoja.anchoBase = d.readUInt16LE(0) / 256;
                } else if (tipo === 0x0208 && d.length >= 16) {
                    const fila = d.readUInt16LE(0);
                    const alto = d.readUInt16LE(6) & 0x7fff;
                    if (alto) hoja.altos.set(fila, alto / 20);
                    if (d.readUInt16LE(12) & 0x20) hoja.ocultas.filas.add(fila);
                } else if (tipo === 0x0225 && d.length >= 4) {
                    hoja.altoBase = (d.readUInt16LE(2) || 255) / 20;
                }
            } catch (_) { /* una celda rara no frena el resto */ }
        }
        hojas.push(hoja);
    }
    return { hojas };
}

// =====================================================================
// .xlsx (un ZIP con XML adentro)
// =====================================================================
function leerZip(buffer) {
    let fin = -1;
    for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 66000); i--) {
        if (buffer.readUInt32LE(i) === 0x06054b50) { fin = i; break; }
    }
    if (fin < 0) throw new Error('No es un archivo de Excel válido');
    const cantidad = buffer.readUInt16LE(fin + 10);
    let pos = buffer.readUInt32LE(fin + 16);
    const archivos = new Map();
    for (let i = 0; i < cantidad && pos + 46 <= buffer.length; i++) {
        if (buffer.readUInt32LE(pos) !== 0x02014b50) break;
        const metodo = buffer.readUInt16LE(pos + 10);
        const comprimido = buffer.readUInt32LE(pos + 20);
        const largoNombre = buffer.readUInt16LE(pos + 28);
        const largoExtra = buffer.readUInt16LE(pos + 30);
        const largoComentario = buffer.readUInt16LE(pos + 32);
        const local = buffer.readUInt32LE(pos + 42);
        const nombre = buffer.toString('utf8', pos + 46, pos + 46 + largoNombre);
        archivos.set(nombre, { metodo, comprimido, local });
        pos += 46 + largoNombre + largoExtra + largoComentario;
    }
    return (nombre) => {
        const entrada = archivos.get(nombre);
        if (!entrada) return null;
        const p = entrada.local;
        const inicio = p + 30 + buffer.readUInt16LE(p + 26) + buffer.readUInt16LE(p + 28);
        const datos = buffer.subarray(inicio, inicio + entrada.comprimido);
        const crudo = entrada.metodo === 8 ? zlib.inflateRawSync(datos, { maxOutputLength: 50 * 1024 * 1024 }) : datos;
        return crudo.toString('utf8');
    };
}

function entidades(texto) {
    return texto
        .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'")
        .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
        .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
        .replace(/&amp;/g, '&');
}

function textoDeNodo(xml) {
    let texto = '';
    for (const parte of xml.matchAll(/<(?:\w+:)?t(?:\s[^>]*)?>([\s\S]*?)<\/(?:\w+:)?t>/g)) texto += parte[1];
    return entidades(texto);
}

function referencia(ref) {
    const partes = /^([A-Z]+)(\d+)$/.exec(ref);
    if (!partes) return null;
    let columna = 0;
    for (const letra of partes[1]) columna = columna * 26 + (letra.charCodeAt(0) - 64);
    return { fila: Number(partes[2]) - 1, columna: columna - 1 };
}

function atributo(texto, nombre) {
    const encontrado = new RegExp(`\\b${nombre}="([^"]*)"`).exec(texto || '');
    return encontrado ? encontrado[1] : null;
}

function bloques(xml, etiqueta) {
    return [...String(xml || '').matchAll(new RegExp(`<(?:\\w+:)?${etiqueta}\\b([^>]*?)(?:\\/>|>([\\s\\S]*?)<\\/(?:\\w+:)?${etiqueta}>)`, 'g'))]
        .map((m) => ({ atributos: m[1] || '', contenido: m[2] || '' }));
}

// Estilos del libro: cada número de estilo de celda ("s") apunta a una fuente, un borde y una alineación.
function estilosXlsx(xml) {
    const seccion = (nombre) => {
        const m = new RegExp(`<(?:\\w+:)?${nombre}\\b[^>]*>([\\s\\S]*?)<\\/(?:\\w+:)?${nombre}>`).exec(xml || '');
        return m ? m[1] : '';
    };
    const fuentes = bloques(seccion('fonts'), 'font').map(({ contenido }) => ({
        n: /<(?:\w+:)?b(\s[^>]*)?\/?>/.test(contenido) && !/<(?:\w+:)?b\s+val="(0|false)"/.test(contenido),
        z: Number(atributo((/<(?:\w+:)?sz\b[^>]*>/.exec(contenido) || [''])[0], 'val')) || 11,
    }));
    const bordes = bloques(seccion('borders'), 'border').map(({ contenido }) => ['left', 'right', 'top', 'bottom'].map((lado) => {
        const m = new RegExp(`<(?:\\w+:)?${lado}\\b([^>]*)`).exec(contenido);
        const estilo = m && atributo(m[1], 'style');
        return estilo && estilo !== 'none' ? 1 : 0;
    }));
    return bloques(seccion('cellXfs'), 'xf').map(({ atributos, contenido }) => {
        const fuente = fuentes[Number(atributo(atributos, 'fontId')) || 0] || { n: false, z: 11 };
        const alineacion = (/<(?:\w+:)?alignment\b([^>]*)/.exec(contenido) || ['', ''])[1];
        const giro = Number(atributo(alineacion, 'textRotation')) || 0;
        return {
            b: bordes[Number(atributo(atributos, 'borderId')) || 0] || [0, 0, 0, 0],
            h: { left: 'l', center: 'c', centerContinuous: 'c', right: 'r' }[atributo(alineacion, 'horizontal')] || '',
            v: { top: 't', center: 'c', bottom: 'b' }[atributo(alineacion, 'vertical')] || 'b',
            w: ['1', 'true'].includes(atributo(alineacion, 'wrapText')),
            r: giro === 255 ? 255 : giro > 90 ? -(giro - 90) : giro,
            n: fuente.n,
            z: fuente.z,
        };
    });
}

function leerXlsx(buffer) {
    const leer = leerZip(buffer);
    const libro = leer('xl/workbook.xml');
    if (!libro) throw new Error('El archivo no tiene una hoja de Excel');
    const relaciones = leer('xl/_rels/workbook.xml.rels') || '';
    const destinos = new Map();
    for (const rel of relaciones.matchAll(/<Relationship\b[^>]*>/g)) {
        const id = atributo(rel[0], 'Id');
        const destino = atributo(rel[0], 'Target');
        if (id && destino) destinos.set(id, destino.replace(/^\/?xl\//, '').replace(/^\//, ''));
    }
    const compartidos = [];
    for (const item of (leer('xl/sharedStrings.xml') || '').matchAll(/<(?:\w+:)?si>([\s\S]*?)<\/(?:\w+:)?si>/g)) compartidos.push(textoDeNodo(item[1]));
    const formatos = estilosXlsx(leer('xl/styles.xml'));

    const hojas = [];
    for (const declarada of libro.matchAll(/<(?:\w+:)?sheet\b[^>]*>/g)) {
        const nombre = atributo(declarada[0], 'name');
        const id = atributo(declarada[0], 'r:id');
        const destino = id && destinos.get(id);
        const xml = destino ? leer(`xl/${destino}`) : null;
        if (!xml) continue;
        const hoja = nuevaHoja(entidades(nombre || 'Hoja'));
        const formato = /<(?:\w+:)?sheetFormatPr\b([^>]*)/.exec(xml);
        if (formato) {
            hoja.altoBase = Number(atributo(formato[1], 'defaultRowHeight')) || hoja.altoBase;
            hoja.anchoBase = Number(atributo(formato[1], 'defaultColWidth')) || hoja.anchoBase;
        }
        for (const { atributos } of bloques(xml, 'col')) {
            const desde = Number(atributo(atributos, 'min')) - 1;
            const hasta = Math.min(Number(atributo(atributos, 'max')) - 1, desde + 255);
            for (let c = desde; c <= hasta; c++) {
                if (atributo(atributos, 'width')) hoja.anchos.set(c, Number(atributo(atributos, 'width')));
                if (['1', 'true'].includes(atributo(atributos, 'hidden'))) hoja.ocultas.columnas.add(c);
            }
        }
        for (const fila of xml.matchAll(/<(?:\w+:)?row\b([^>]*)>/g)) {
            const numero = Number(atributo(fila[1], 'r')) - 1;
            if (atributo(fila[1], 'ht')) hoja.altos.set(numero, Number(atributo(fila[1], 'ht')));
            if (['1', 'true'].includes(atributo(fila[1], 'hidden'))) hoja.ocultas.filas.add(numero);
        }
        for (const celda of xml.matchAll(/<(?:\w+:)?c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/(?:\w+:)?c>)/g)) {
            const atributos = celda[1];
            const contenido = celda[2] || '';
            const ref = atributo(atributos, 'r');
            const posicion = ref && referencia(ref);
            if (!posicion) continue;
            const s = atributo(atributos, 's');
            if (s !== null) ponerEstilo(hoja, posicion.fila, posicion.columna, formatos[Number(s)] || null);
            const tipo = atributo(atributos, 't');
            const valor = /<(?:\w+:)?v>([\s\S]*?)<\/(?:\w+:)?v>/.exec(contenido);
            let texto = null;
            if (tipo === 's' && valor) texto = compartidos[Number(valor[1])];
            else if (tipo === 'inlineStr') texto = textoDeNodo(contenido);
            else if (valor) texto = tipo === 'str' || tipo === 'b' || tipo === 'e' ? entidades(valor[1]) : numeroComoTexto(Number(valor[1]));
            ponerCelda(hoja, posicion.fila, posicion.columna, texto);
        }
        for (const combinada of xml.matchAll(/<(?:\w+:)?mergeCell\b[^>]*ref="([A-Z]+\d+):([A-Z]+\d+)"/g)) {
            const a = referencia(combinada[1]);
            const b = referencia(combinada[2]);
            if (a && b) hoja.combinadas.push({ f1: a.fila, c1: a.columna, f2: b.fila, c2: b.columna });
        }
        hojas.push(hoja);
    }
    return { hojas };
}

function leerPlanilla(buffer) {
    if (!Buffer.isBuffer(buffer) || buffer.length < 8) throw new Error('El archivo está vacío');
    if (buffer.readUInt32LE(0) === 0xe011cfd0) return leerXls(buffer);
    if (buffer.readUInt32LE(0) === 0x04034b50) return leerXlsx(buffer);
    throw new Error('El archivo tiene que ser una planilla de Excel (.xls o .xlsx)');
}

module.exports = { leerPlanilla, tieneBorde };
