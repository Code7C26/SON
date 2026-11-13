// Formularios de control (tableros, extintores, almacenaje, baños...): el administrador sube el Excel
// que ya usan, el sistema lo convierte en un formulario digital, el técnico lo completa en la app y
// sale en el informe como tarea realizada.
//
// Un formulario es de uno de estos tipos:
//  - 'excel': la planilla tal cual es en Excel (celdas, bordes, anchos). El técnico completa los
//    casilleros vacíos y el informe la muestra igual. Es lo que se usa al subir un Excel: no hay
//    conversión, así que no hay errores de conversión.
//  - 'lista': preguntas fijas, cada una con su respuesta (SI / NO / NC) y una observación. Puede tener
//    varias columnas (por ejemplo Baño M, Baño H, Vestuario, Comedor) y títulos de sección.
//  - 'planilla': una fila por cada cosa que se revisa (un tablero, un extintor, una máquina). Cada fila
//    tiene campos: texto, número, fecha u opciones (SI / NO / NC, S / I...).
// 'lista' y 'planilla' quedan para los formularios que se arman a mano.
const { leerPlanilla, tieneBorde } = require('./excel');

const MAX_FILAS_EXCEL = 150;
const MAX_COLUMNAS_EXCEL = 45;
const MAX_CELDAS_EXCEL = 6000;

const VERSION = 1;
const TIPOS_CAMPO = ['texto', 'numero', 'fecha', 'opciones'];
const MAX_PREGUNTAS = 200;
const MAX_CAMPOS = 40;
const MAX_COLUMNAS = 12;
const MAX_FILAS = 300;
const MAX_ARCHIVO = 6 * 1024 * 1024;

// Palabras que en estos Excel marcan una columna de respuesta.
const RESPUESTAS = new Set(['SI', 'SÍ', 'NO', 'NC', 'N/C', 'NA', 'N/A', 'BIEN', 'MAL', 'REGULAR', 'S', 'I', 'B', 'R', 'M', 'CUMPLE', 'NO CUMPLE', 'OK', 'X']);
const FIN_DEL_FORMULARIO = /^(firma|revisado por|referencia|personal\s*\(|observaciones?\s*:?$)/i;

function texto(valor, maximo = 300) {
    return String(valor ?? '').replace(/\s+/g, ' ').trim().slice(0, maximo);
}

// "VENCIMIENTO CARGA" -> "Vencimiento carga". Los textos que ya tienen minúsculas quedan como están.
function prolijo(valor, maximo = 300) {
    let limpio = texto(valor, maximo).replace(/\s*:\s*$/, '');
    const letras = limpio.replace(/[^A-Za-zÁÉÍÓÚÑáéíóúñ]/g, '');
    const mayusculas = letras.replace(/[^A-ZÁÉÍÓÚÑ]/g, '').length;
    // Casi todo en mayúsculas ("CONTROL DE BAÑOS, VESTUARIOS y COMEDOR"): se pasa a oración.
    if (letras.length > 3 && mayusculas / letras.length > 0.8) {
        limpio = limpio.toLowerCase().replace(/^(¿?\s*)(\p{L})/u, (_, signo, letra) => signo + letra.toUpperCase());
        limpio = limpio.replace(/\b(epp|pat|ph|kg|ader|eess|ypf)\b/gi, (sigla) => sigla.toUpperCase());
        limpio = limpio.replace(/(\s)([a-zñ])$/u, (_, espacio, letra) => espacio + letra.toUpperCase()); // "Baño m" -> "Baño M"
    }
    return limpio;
}

function nombreDesdeArchivo(archivo) {
    return prolijo(String(archivo || 'Formulario')
        .replace(/\.[a-z0-9]+$/i, '')
        .replace(/^[\d\s.\-_]+/, '')
        .replace(/[_]+/g, ' '), 80) || 'Formulario';
}

function nombreDesdeTitulo(titulo) {
    const limpio = String(titulo || '')
        .replace(/^[\d\s.\-–]+/, '')
        .replace(/check\s*-?\s*list\s*-?/i, '')
        .replace(/^planilla\s+de\s+/i, '')
        .replace(/^\s*[-–]\s*/, '');
    return prolijo(limpio, 80);
}

// Nombre de cada fila de una planilla, para el botón "Agregar ..." de la app.
function elementoDe(nombre) {
    const n = nombre.toLowerCase();
    const opciones = [
        [/extintor|matafuego/, 'Extintor'], [/tablero/, 'Tablero'], [/herramient|m[aá]quina|equipo/, 'Máquina o herramienta'],
        [/escape|salida|puerta|evacuaci/, 'Puerta o salida'], [/veh[ií]culo|m[oó]vil/, 'Vehículo'], [/escalera/, 'Escalera'],
        [/compresor/, 'Compresor'], [/epp|persona|personal/, 'Persona'], [/botiqu/, 'Botiquín'],
    ];
    for (const [patron, elemento] of opciones) if (patron.test(n)) return elemento;
    return 'Elemento';
}

function tipoDeColumna(etiqueta, hayReferencia) {
    const t = etiqueta.toLowerCase();
    if (/venc|fecha/.test(t)) return 'fecha';
    if (/capacidad|\bkg\b|cantidad|presi[oó]n\s*\(|litros/.test(t)) return 'numero';
    if (/^n[º°o.]?\s*$|^n[º°]|n[uú]mero|tipo|legajo|cuil|ader|marca|modelo|patente|dominio|sector|denominaci/.test(t)) return 'texto';
    return hayReferencia ? 'opciones' : 'texto';
}

// =====================================================================
// CONVERSIÓN: de la hoja de Excel a la definición del formulario
// =====================================================================
function convertirHoja(hoja, archivo) {
    const avisos = [];
    const celda = (f, c) => hoja.celdas.get(`${f},${c}`) || '';
    const combinada = (f, c) => hoja.combinadas.find((m) => f >= m.f1 && f <= m.f2 && c >= m.c1 && c <= m.c2) || null;
    const finDeCelda = (f, c) => (combinada(f, c) || { c2: c }).c2;
    const filaComoLista = (f) => {
        const lista = [];
        for (let c = 0; c < hoja.columnas; c++) if (celda(f, c)) lista.push({ c, valor: celda(f, c) });
        return lista;
    };
    const esRespuesta = (valor) => RESPUESTAS.has(texto(valor).toUpperCase());

    // Título: la primera celda que nombra el control (no el membrete "Servicio de higiene...").
    let nombre = '';
    for (let f = 0; f < Math.min(hoja.filas, 12) && !nombre; f++) {
        for (const { valor } of filaComoLista(f)) {
            if (/control|check|planilla|inspecci|relevamiento/i.test(valor) && !/^servicio/i.test(valor) && valor.length < 120) {
                nombre = nombreDesdeTitulo(valor);
                break;
            }
        }
    }
    if (!nombre) nombre = nombreDesdeArchivo(archivo);

    // Fila con las respuestas (SI / NO / NC): marca dónde están las columnas que se contestan.
    let filaRespuestas = -1;
    for (let f = 0; f < hoja.filas; f++) {
        if (filaComoLista(f).filter(({ valor }) => esRespuesta(valor)).length >= 2) { filaRespuestas = f; break; }
    }

    // ¿Dónde termina? En la firma, la referencia o las observaciones generales (en la primera columna;
    // una columna "Observaciones" del encabezado no cuenta).
    let filaFinal = hoja.filas;
    for (let f = Math.max(filaRespuestas + 1, 6); f < hoja.filas; f++) {
        const fin = filaComoLista(f).some(({ c, valor }) => {
            const limpio = valor.trim();
            if (/^(firma|revisado por|referencia|personal\s*\()/i.test(limpio)) return true;
            return c === 0 && FIN_DEL_FORMULARIO.test(limpio);
        });
        if (fin) { filaFinal = f; break; }
    }
    const hayReferencia = [...hoja.celdas.values()].some((v) => /\(s\)/i.test(v) && /\(i\)/i.test(v));

    if (filaRespuestas >= 0) {
        // Grupos de columnas de respuesta: cada vez que vuelve a aparecer la primera opción empieza otro.
        const celdasRespuesta = filaComoLista(filaRespuestas).filter(({ valor }) => esRespuesta(valor));
        const primera = texto(celdasRespuesta[0].valor).toUpperCase();
        const grupos = [];
        for (const { c, valor } of celdasRespuesta) {
            const opcion = texto(valor).toUpperCase().replace('SÍ', 'SI');
            if (!grupos.length || opcion === primera) grupos.push({ c1: c, c2: finDeCelda(filaRespuestas, c), opciones: [] });
            const grupo = grupos[grupos.length - 1];
            if (!grupo.opciones.includes(opcion)) grupo.opciones.push(opcion);
            grupo.c2 = finDeCelda(filaRespuestas, c);
        }
        const primeraColumnaRespuesta = grupos[0].c1;
        const opciones = grupos.reduce((mas, g) => (g.opciones.length > mas.length ? g.opciones : mas), grupos[0].opciones);

        // Arriba de la fila de respuestas están los títulos de cada grupo (pregunta o sector).
        // Una fila vacía corta el encabezado, salvo que esté tapada por una celda combinada de arriba.
        const tapada = (f) => hoja.combinadas.some((m) => m.f1 < f && m.f2 >= f);
        const inicioEncabezado = (() => {
            for (let f = filaRespuestas - 1; f >= 0; f--) {
                const fila = filaComoLista(f);
                if (!fila.length && !tapada(f)) return f + 1;
                if (fila.length && fila.length <= 2 && fila.every(({ valor }) => /control|check|planilla|servicio|empresa|fecha|muestra/i.test(valor))) return f + 1;
            }
            return 0;
        })();
        const tituloDe = (c1, c2) => {
            for (let f = filaRespuestas; f >= inicioEncabezado; f--) {
                for (let c = c1; c <= c2; c++) {
                    const valor = celda(f, c);
                    if (valor && !esRespuesta(valor)) return valor;
                }
                for (const m of hoja.combinadas) {
                    if (m.f1 <= f && m.f2 >= f && m.c1 <= c1 && m.c2 >= c1 && celda(m.f1, m.c1) && !esRespuesta(celda(m.f1, m.c1)) && m.c1 >= c1 - 0) {
                        return celda(m.f1, m.c1);
                    }
                }
            }
            return '';
        };

        // ¿Hay preguntas escritas en las filas de abajo, a la izquierda? Entonces es una lista.
        const preguntas = [];
        for (let f = filaRespuestas + 1; f < filaFinal; f++) {
            let valor = '';
            let columna = -1;
            for (let c = 0; c < primeraColumnaRespuesta; c++) {
                if (celda(f, c)) { valor = celda(f, c); columna = c; break; }
            }
            // Fuera: marcadores "(1)" y notas al pie largas que no son preguntas.
            if (!valor || /^\(\d+\)/.test(valor.trim()) || valor.length > 400) continue;
            const ancho = finDeCelda(f, columna);
            preguntas.push({ texto: prolijo(valor), seccion: ancho >= primeraColumnaRespuesta && valor.length < 60 });
        }

        if (preguntas.filter((p) => !p.seccion).length >= 2) {
            // Columnas (Baño M, Baño H...): solo si los grupos tienen títulos distintos.
            const titulos = grupos.map((g) => prolijo(tituloDe(g.c1, g.c2), 40));
            const distintos = new Set(titulos.filter(Boolean));
            const columnas = grupos.length > 1 && distintos.size === grupos.length ? titulos : [];
            if (grupos.length > 1 && !columnas.length) avisos.push('El Excel repite las mismas columnas de respuesta (por ejemplo, dos personas lado a lado): se dejó una sola. Revisalo.');
            if (preguntas.some((p) => p.texto.length < 3)) avisos.push('Hay renglones muy cortos: revisá que sean preguntas.');
            return {
                nombre,
                avisos,
                definicion: { version: VERSION, tipo: 'lista', opciones, columnas, preguntas: preguntas.slice(0, MAX_PREGUNTAS) },
            };
        }

        // Si no hay preguntas a la izquierda, es una planilla: cada grupo de respuesta es una pregunta.
        let identificador = '';
        for (let f = filaRespuestas; f >= inicioEncabezado && !identificador; f--) {
            for (let c = 0; c < primeraColumnaRespuesta; c++) if (celda(f, c)) { identificador = celda(f, c); break; }
        }
        const campos = [{ etiqueta: prolijo(identificador.replace(/^indicar\s+/i, ''), 120) || elementoDe(nombre), tipo: 'texto' }];
        const usadas = new Set();
        for (const grupo of grupos) {
            const pregunta = tituloDe(grupo.c1, grupo.c2);
            for (let c = grupo.c1; c <= grupo.c2; c++) usadas.add(c);
            if (!pregunta || /observac/i.test(pregunta)) {
                if (!pregunta) avisos.push('Había columnas de respuesta sin pregunta escrita: se dejaron afuera.');
                continue;
            }
            campos.push({ etiqueta: prolijo(pregunta, 200), tipo: 'opciones', opciones: grupo.opciones });
        }
        // Otras columnas con título (por ejemplo "Si se emite AdeR, indicar su número").
        for (let c = primeraColumnaRespuesta; c < hoja.columnas; c++) {
            if (usadas.has(c)) continue;
            const titulo = tituloDe(c, c);
            if (!titulo || /observac/i.test(titulo) || campos.some((campo) => campo.etiqueta === prolijo(titulo, 200))) continue;
            campos.push({ etiqueta: prolijo(titulo, 200), tipo: tipoDeColumna(titulo, false) });
            for (let k = c; k <= finDeCelda(inicioEncabezado, c); k++) usadas.add(k);
        }
        return {
            nombre,
            avisos: [...new Set(avisos)],
            definicion: { version: VERSION, tipo: 'planilla', elemento: elementoDe(nombre), opciones, campos: campos.slice(0, MAX_CAMPOS) },
        };
    }

    // Sin columnas SI / NO: una planilla de datos (por ejemplo extintores). La fila de títulos es la que
    // tiene más columnas escritas antes del final.
    let mejor = -1;
    let mejorCantidad = 0;
    for (let f = 0; f < filaFinal; f++) {
        const cantidad = filaComoLista(f).filter(({ valor }) => valor.length < 80).length;
        if (cantidad > mejorCantidad) { mejor = f; mejorCantidad = cantidad; }
    }
    if (mejor < 0 || mejorCantidad < 2) {
        return { nombre, avisos: ['No se reconoció la forma del formulario: cargá las preguntas a mano.'], definicion: { version: VERSION, tipo: 'lista', opciones: ['SI', 'NO', 'NC'], columnas: [], preguntas: [] } };
    }
    const titulos = filaComoLista(mejor);
    const opcionesReferencia = hayReferencia ? ['S', 'I'] : ['SI', 'NO', 'NC'];
    const campos = titulos.map(({ valor }, indice) => {
        const etiqueta = prolijo(valor, 200);
        if (indice === 0) return { etiqueta, tipo: 'texto' };
        const tipo = tipoDeColumna(valor, hayReferencia);
        return tipo === 'opciones' ? { etiqueta, tipo, opciones: opcionesReferencia } : { etiqueta, tipo };
    }).filter((campo) => !/observac/i.test(campo.etiqueta));
    if (hayReferencia) avisos.push('Las columnas de control se cargaron con S (satisfactorio) / I (insatisfactorio), como dice la referencia del Excel.');
    return {
        nombre,
        avisos,
        definicion: { version: VERSION, tipo: 'planilla', elemento: elementoDe(nombre), opciones: opcionesReferencia, campos: campos.slice(0, MAX_CAMPOS) },
    };
}

// =====================================================================
// IGUAL AL EXCEL: la planilla se guarda tal cual y el técnico completa los casilleros vacíos.
// =====================================================================
const ETIQUETA_AUTOMATICA = /^(empresa|raz[oó]n social|cliente|fecha(\s+de\s+(realizaci[oó]n|emisi[oó]n|control))?)\s*:?\s*$/i;

function nombreDeHoja(hoja, archivo) {
    for (let f = 0; f < Math.min(hoja.filas, 12); f++) {
        for (let c = 0; c < hoja.columnas; c++) {
            const valor = hoja.celdas.get(`${f},${c}`);
            if (valor && /control|check|planilla|inspecci|relevamiento/i.test(valor) && !/^servicio/i.test(valor) && valor.length < 120) return nombreDesdeTitulo(valor);
        }
    }
    return nombreDesdeArchivo(archivo);
}

function planillaDesdeHoja(hoja, archivo) {
    const avisos = [];
    const clave = (f, c) => `${f},${c}`;
    const combinadaEn = (f, c) => hoja.combinadas.find((m) => f >= m.f1 && f <= m.f2 && c >= m.c1 && c <= m.c2) || null;
    const estilo = (f, c) => hoja.estilos.get(clave(f, c)) || null;
    const esRespuesta = (valor) => RESPUESTAS.has(texto(valor).toUpperCase());

    // Hasta dónde llega el formulario: la última celda con texto o con borde.
    let ultimaFila = 0;
    let ultimaColumna = 0;
    for (const k of hoja.celdas.keys()) {
        const [f, c] = k.split(',').map(Number);
        ultimaFila = Math.max(ultimaFila, f);
        ultimaColumna = Math.max(ultimaColumna, c);
    }
    for (const [k, e] of hoja.estilos) {
        if (!tieneBorde(e)) continue;
        const [f, c] = k.split(',').map(Number);
        ultimaFila = Math.max(ultimaFila, f);
        ultimaColumna = Math.max(ultimaColumna, c);
    }
    for (const m of hoja.combinadas) {
        if (hoja.celdas.has(clave(m.f1, m.c1))) {
            ultimaFila = Math.max(ultimaFila, m.f2);
            ultimaColumna = Math.max(ultimaColumna, m.c2);
        }
    }
    if (ultimaFila >= MAX_FILAS_EXCEL || ultimaColumna >= MAX_COLUMNAS_EXCEL) {
        avisos.push('La planilla es muy grande: se tomó solo la parte de arriba a la izquierda.');
        ultimaFila = Math.min(ultimaFila, MAX_FILAS_EXCEL - 1);
        ultimaColumna = Math.min(ultimaColumna, MAX_COLUMNAS_EXCEL - 1);
    }

    // Medidas en puntos (como en la hoja impresa). Las filas y columnas ocultas no se muestran.
    const anchoEnPuntos = (caracteres) => Math.round((caracteres * 7 + 5) * 0.75 * 10) / 10;
    const anchos = [];
    for (let c = 0; c <= ultimaColumna; c++) anchos.push(hoja.ocultas.columnas.has(c) ? 0 : anchoEnPuntos(hoja.anchos.has(c) ? hoja.anchos.get(c) : hoja.anchoBase));
    const altos = [];
    for (let f = 0; f <= ultimaFila; f++) altos.push(hoja.ocultas.filas.has(f) ? 0 : Math.round((hoja.altos.has(f) ? hoja.altos.get(f) : hoja.altoBase) * 10) / 10);

    // Cada celda (o grupo de celdas combinadas) con su texto y su formato.
    const celdas = [];
    const ocupadas = new Set();
    for (let f = 0; f <= ultimaFila; f++) {
        for (let c = 0; c <= ultimaColumna; c++) {
            if (ocupadas.has(clave(f, c))) continue;
            const m = combinadaEn(f, c);
            const f2 = m ? Math.min(m.f2, ultimaFila) : f;
            const c2 = m ? Math.min(m.c2, ultimaColumna) : c;
            if (m) for (let ff = f; ff <= f2; ff++) for (let cc = c; cc <= c2; cc++) ocupadas.add(clave(ff, cc));
            const base = estilo(f, c) || {};
            // En una celda combinada, cada borde sale de la celda de ese lado.
            const b = [
                (estilo(f, c) || {}).b ? estilo(f, c).b[0] : 0,
                (estilo(f, c2) || {}).b ? estilo(f, c2).b[1] : 0,
                (estilo(f, c) || {}).b ? estilo(f, c).b[2] : 0,
                (estilo(f2, c) || {}).b ? estilo(f2, c).b[3] : 0,
            ];
            const valor = hoja.celdas.get(clave(f, c)) || '';
            if (!valor && !b.some(Boolean)) continue;
            const celda = { f, c, b };
            if (f2 > f) celda.f2 = f2;
            if (c2 > c) celda.c2 = c2;
            if (valor) celda.t = valor.slice(0, 500);
            if (base.h) celda.h = base.h;
            if (base.v && base.v !== 'b') celda.v = base.v;
            if (base.w) celda.w = true;
            if (base.r) celda.r = base.r;
            if (base.n) celda.n = true;
            if (base.z && base.z !== 10) celda.z = base.z;
            if (valor && ETIQUETA_AUTOMATICA.test(valor.trim())) celda.auto = /fecha/i.test(valor) ? 'fecha' : 'empresa';
            celdas.push(celda);
            if (celdas.length >= MAX_CELDAS_EXCEL) break;
        }
        if (celdas.length >= MAX_CELDAS_EXCEL) break;
    }

    // Texto que cubre una posición (aunque esté en una celda combinada).
    const textoEn = (f, c) => {
        const m = combinadaEn(f, c);
        return hoja.celdas.get(m ? clave(m.f1, m.c1) : clave(f, c)) || '';
    };
    // Grupos de respuesta de cada fila de títulos (SI NO NC | SI NO NC ...): solo se marca una por grupo.
    const gruposPorFila = new Map();
    const grupoDe = (fila, columna) => {
        if (!gruposPorFila.has(fila)) {
            const lista = [];
            let primera = null;
            let indice = -1;
            for (let c = 0; c <= ultimaColumna; c++) {
                const valor = texto(hoja.celdas.get(clave(fila, c))).toUpperCase();
                if (!RESPUESTAS.has(valor)) continue;
                if (primera === null) primera = valor;
                if (valor === primera || indice < 0) indice += 1;
                lista.push({ c, indice });
            }
            gruposPorFila.set(fila, lista);
        }
        const encontrado = gruposPorFila.get(fila).find((g) => g.c === columna);
        return encontrado ? `${fila}-${encontrado.indice}` : null;
    };

    // Casilleros: las celdas vacías con borde. Su tipo sale del título de la columna.
    const campos = [];
    for (const celda of celdas) {
        if (celda.t || !celda.b.some(Boolean)) continue;
        let encabezado = '';
        let filaEncabezado = -1;
        let opcion = null;
        let grupo = null;
        for (let f = celda.f - 1; f >= Math.max(0, celda.f - 20); f--) {
            const valor = textoEn(f, celda.c);
            if (!valor) continue;
            // Un título que arranca en la primera columna y cruza la fila (por ejemplo "LUCES") es de
            // la sección, no de esta columna: se sigue buscando hacia arriba.
            const tapa = combinadaEn(f, celda.c);
            if (celda.c > 0 && tapa && tapa.c1 === 0) continue;
            if (esRespuesta(valor) && !opcion) {
                opcion = texto(valor).toUpperCase().replace('SÍ', 'SI');
                grupo = grupoDe(f, (combinadaEn(f, celda.c) || { c1: celda.c }).c1);
                continue; // sigue subiendo para encontrar la pregunta
            }
            encabezado = valor;
            filaEncabezado = f;
            break;
        }
        const campo = { f: celda.f, c: celda.c, tipo: 'texto' };
        if (opcion) {
            campo.tipo = 'marca';
            campo.opcion = opcion;
            if (grupo) campo.grupo = grupo;
        } else if (/venc/i.test(encabezado) || (/fecha/i.test(encabezado) && celda.f - ((combinadaEn(filaEncabezado, celda.c) || { f2: filaEncabezado }).f2) <= 1)) {
            // "Vencimiento" en el título de la columna, o "Fecha" justo arriba del casillero.
            campo.tipo = 'fecha';
        }
        if (encabezado) campo.encabezado = prolijo(encabezado, 160);
        campos.push(campo);
    }
    if (!campos.length) avisos.push('No se encontraron casilleros con borde para completar. Revisá el Excel: el técnico no va a poder cargar nada.');
    const opciones = [...new Set(campos.filter((c) => c.opcion).map((c) => c.opcion))];
    // Respuestas rápidas para los casilleros de texto ("REFERENCIA: SATISFACTORIO (S) - INSATISFACTORIO (I)").
    const sugerencias = [...hoja.celdas.values()].some((v) => /\(s\)/i.test(v) && /\(i\)/i.test(v)) ? ['S', 'I'] : [];
    return {
        nombre: nombreDeHoja(hoja, archivo),
        avisos,
        definicion: { version: VERSION, tipo: 'excel', anchos, altos, celdas, campos, opciones, sugerencias },
    };
}

function convertirExcel(buffer, archivo) {
    const { hojas } = leerPlanilla(buffer);
    const conDatos = hojas.filter((hoja) => hoja.celdas.size > 0);
    if (!conDatos.length) throw new Error('La planilla está vacía');
    // La hoja con más texto es la del formulario (las otras suelen estar vacías).
    const hoja = conDatos.reduce((mas, h) => (h.celdas.size > mas.celdas.size ? h : mas), conDatos[0]);
    const resultado = planillaDesdeHoja(hoja, archivo);
    if (conDatos.length > 1) resultado.avisos.push(`El Excel tiene ${conDatos.length} hojas con datos: se usó "${hoja.nombre}".`);
    return { ...resultado, definicion: limpiarDefinicion(resultado.definicion).definicion };
}

// Lo que vuelve del panel se controla igual: números en rango, textos cortos, tamaños con límite.
function limpiarPlanillaExcel(entrada) {
    const numero = (valor, maximo) => {
        const n = Number(valor);
        return Number.isFinite(n) && n >= 0 && n <= maximo ? n : null;
    };
    const anchos = (Array.isArray(entrada.anchos) ? entrada.anchos : []).slice(0, MAX_COLUMNAS_EXCEL).map((a) => numero(a, 1000) ?? 48);
    const altos = (Array.isArray(entrada.altos) ? entrada.altos : []).slice(0, MAX_FILAS_EXCEL).map((a) => numero(a, 500) ?? 13);
    if (!anchos.length || !altos.length) return { error: 'La planilla está vacía' };
    const dentro = (f, c) => Number.isInteger(f) && Number.isInteger(c) && f >= 0 && c >= 0 && f < altos.length && c < anchos.length;
    const celdas = [];
    for (const celda of (Array.isArray(entrada.celdas) ? entrada.celdas : []).slice(0, MAX_CELDAS_EXCEL)) {
        if (!celda || !dentro(celda.f, celda.c)) continue;
        const limpia = { f: celda.f, c: celda.c, b: (Array.isArray(celda.b) ? celda.b : [0, 0, 0, 0]).slice(0, 4).map((x) => (Number.isInteger(x) && x >= 0 && x <= 15 ? x : 0)) };
        while (limpia.b.length < 4) limpia.b.push(0);
        if (dentro(celda.f2, celda.c) && celda.f2 > celda.f) limpia.f2 = celda.f2;
        if (dentro(celda.f, celda.c2) && celda.c2 > celda.c) limpia.c2 = celda.c2;
        if (celda.t) limpia.t = String(celda.t).slice(0, 500);
        if (['l', 'c', 'r'].includes(celda.h)) limpia.h = celda.h;
        if (['t', 'c'].includes(celda.v)) limpia.v = celda.v;
        if (celda.w) limpia.w = true;
        if ([90, -90, 255].includes(celda.r) || (Number.isInteger(celda.r) && Math.abs(celda.r) <= 90)) limpia.r = celda.r;
        if (celda.n) limpia.n = true;
        if (numero(celda.z, 72)) limpia.z = numero(celda.z, 72);
        if (['empresa', 'fecha'].includes(celda.auto)) limpia.auto = celda.auto;
        celdas.push(limpia);
    }
    const campos = [];
    const vistos = new Set();
    for (const campo of (Array.isArray(entrada.campos) ? entrada.campos : []).slice(0, MAX_CELDAS_EXCEL)) {
        if (!campo || !dentro(campo.f, campo.c) || vistos.has(`${campo.f},${campo.c}`)) continue;
        vistos.add(`${campo.f},${campo.c}`);
        const limpio = { f: campo.f, c: campo.c, tipo: ['marca', 'fecha', 'texto'].includes(campo.tipo) ? campo.tipo : 'texto' };
        if (limpio.tipo === 'marca') {
            limpio.opcion = texto(campo.opcion, 20) || 'X';
            if (campo.grupo) limpio.grupo = texto(campo.grupo, 20);
        }
        if (campo.encabezado) limpio.encabezado = texto(campo.encabezado, 160);
        campos.push(limpio);
    }
    if (!campos.length) return { error: 'La planilla no tiene casilleros para completar' };
    const opciones = [...new Set(campos.filter((c) => c.opcion).map((c) => c.opcion))];
    const sugerencias = (Array.isArray(entrada.sugerencias) ? entrada.sugerencias : []).map((s) => texto(s, 12)).filter(Boolean).slice(0, 8);
    return { definicion: { version: VERSION, tipo: 'excel', anchos, altos, celdas, campos, opciones, sugerencias } };
}

// =====================================================================
// VALIDACIÓN de lo que manda el panel
// =====================================================================
function listaDeOpciones(valor) {
    if (!Array.isArray(valor)) return null;
    const lista = [];
    for (const item of valor) {
        const limpio = texto(item, 24);
        if (limpio && !lista.includes(limpio)) lista.push(limpio);
    }
    return lista.slice(0, 8);
}

function limpiarDefinicion(entrada) {
    if (!entrada || typeof entrada !== 'object') return { error: 'Falta la definición del formulario' };
    if (entrada.tipo === 'excel') return limpiarPlanillaExcel(entrada);
    const tipo = entrada.tipo === 'planilla' ? 'planilla' : 'lista';
    const opciones = listaDeOpciones(entrada.opciones) || [];
    if (opciones.length < 2) return { error: 'Poné al menos dos opciones de respuesta (por ejemplo SI y NO)' };
    if (tipo === 'lista') {
        const preguntas = (Array.isArray(entrada.preguntas) ? entrada.preguntas : [])
            .map((p) => (typeof p === 'string' ? { texto: p } : p))
            .map((p) => ({ texto: texto(p && p.texto, 400), seccion: Boolean(p && p.seccion) }))
            .filter((p) => p.texto)
            .slice(0, MAX_PREGUNTAS);
        if (!preguntas.some((p) => !p.seccion)) return { error: 'El formulario necesita al menos una pregunta' };
        const columnas = (Array.isArray(entrada.columnas) ? entrada.columnas : []).map((c) => texto(c, 40)).filter(Boolean).slice(0, MAX_COLUMNAS);
        return { definicion: { version: VERSION, tipo, opciones, columnas, preguntas } };
    }
    const campos = [];
    for (const campo of Array.isArray(entrada.campos) ? entrada.campos : []) {
        const etiqueta = texto(campo && campo.etiqueta, 200);
        if (!etiqueta) continue;
        const tipoCampo = TIPOS_CAMPO.includes(campo.tipo) ? campo.tipo : 'texto';
        const limpio = { etiqueta, tipo: tipoCampo };
        if (tipoCampo === 'opciones') {
            const propias = listaDeOpciones(campo.opciones);
            limpio.opciones = propias && propias.length >= 2 ? propias : opciones;
        }
        campos.push(limpio);
        if (campos.length >= MAX_CAMPOS) break;
    }
    if (!campos.length) return { error: 'La planilla necesita al menos un campo' };
    return { definicion: { version: VERSION, tipo, elemento: texto(entrada.elemento, 40) || 'Elemento', opciones, campos } };
}

// Formularios viejos (solo una lista de puntos): se muestran como una lista de preguntas SI / NO.
function definicionDe(fila) {
    if (fila.definicion && typeof fila.definicion === 'object' && fila.definicion.tipo) return fila.definicion;
    const puntos = Array.isArray(fila.puntos) ? fila.puntos : [];
    return { version: VERSION, tipo: 'lista', opciones: ['SI', 'NO', 'NC'], columnas: [], preguntas: puntos.map((p) => ({ texto: texto(p, 400), seccion: false })) };
}

// Copia de los formularios elegidos para una orden: si después se edita el formulario, la orden
// conserva el que tenía cuando se armó.
async function copiaDeFormularios(pool, ids) {
    const lista = (Array.isArray(ids) ? ids : []).map(Number).filter((n) => Number.isInteger(n) && n > 0);
    if (!lista.length) return [];
    const filas = await pool.query('SELECT id, nombre, puntos, definicion FROM formularios_visita WHERE id = ANY($1) AND activo = true', [lista]);
    const porId = new Map(filas.rows.map((fila) => [fila.id, fila]));
    return [...new Set(lista)].filter((id) => porId.has(id)).map((id) => {
        const fila = porId.get(id);
        return { id, nombre: fila.nombre, definicion: definicionDe(fila) };
    });
}

async function formulariosFijosDe(pool, empresaId) {
    if (!empresaId) return [];
    const fila = await pool.query('SELECT formularios_fijos FROM empresas WHERE id = $1', [empresaId]);
    const ids = fila.rows[0] && fila.rows[0].formularios_fijos;
    return Array.isArray(ids) ? copiaDeFormularios(pool, ids) : [];
}

// =====================================================================
// RESPUESTAS del técnico: se acomodan a la definición de la orden (no se confía en la app).
// =====================================================================
function fechaValida(valor) {
    const limpio = String(valor || '').slice(0, 10);
    return /^\d{4}-\d{2}-\d{2}$/.test(limpio) ? limpio : null;
}

function valorDeCampo(campo, valor) {
    if (valor === null || valor === undefined || valor === '') return null;
    if (campo.tipo === 'opciones') return (campo.opciones || []).includes(String(valor)) ? String(valor) : null;
    if (campo.tipo === 'fecha') return fechaValida(valor);
    if (campo.tipo === 'numero') {
        const numero = Number(String(valor).replace(',', '.'));
        return Number.isFinite(numero) ? numero : null;
    }
    return texto(valor, 300) || null;
}

function normalizarRespuestas(formulario, enviado) {
    const d = formulario.definicion;
    const datos = enviado && typeof enviado === 'object' ? enviado : {};
    const observacion = texto(datos.observacion, 2000) || null;
    if (d.tipo === 'excel') {
        // valores: { "fila,columna": valor } solo para los casilleros del formulario.
        const enviados = datos.valores && typeof datos.valores === 'object' ? datos.valores : {};
        const valores = {};
        const marcados = new Set(); // "fila|grupo": una sola marca por grupo en cada fila
        for (const campo of d.campos) {
            const clave = `${campo.f},${campo.c}`;
            const valor = enviados[clave];
            if (valor === null || valor === undefined || valor === '' || valor === false) continue;
            if (campo.tipo === 'marca') {
                const grupo = campo.grupo ? `${campo.f}|${campo.grupo}` : null;
                if (grupo && marcados.has(grupo)) continue;
                if (grupo) marcados.add(grupo);
                valores[clave] = 'X';
            } else if (campo.tipo === 'fecha') {
                const fecha = fechaValida(valor);
                if (fecha) valores[clave] = fecha;
            } else {
                const limpio = texto(valor, 120);
                if (limpio) valores[clave] = limpio;
            }
        }
        const filas = new Set(Object.keys(valores).map((k) => k.split(',')[0]));
        return { id: formulario.id, nombre: formulario.nombre, definicion: d, valores, observacion, contestadas: Object.keys(valores).length, filasCompletadas: filas.size };
    }
    if (d.tipo === 'lista') {
        const columnas = d.columnas && d.columnas.length ? d.columnas.length : 1;
        const respuestas = Array.isArray(datos.respuestas) ? datos.respuestas : [];
        const salida = d.preguntas.map((pregunta, i) => {
            if (pregunta.seccion) return null;
            const r = respuestas[i] && typeof respuestas[i] === 'object' ? respuestas[i] : {};
            const valores = Array.from({ length: columnas }, (_, k) => {
                const v = Array.isArray(r.valores) ? r.valores[k] : null;
                return d.opciones.includes(String(v)) ? String(v) : null;
            });
            return { valores, obs: texto(r.obs, 500) || null };
        });
        const contestadas = salida.filter((r) => r && r.valores.some(Boolean)).length;
        return { id: formulario.id, nombre: formulario.nombre, definicion: d, respuestas: salida, observacion, contestadas };
    }
    const filas = (Array.isArray(datos.filas) ? datos.filas : []).slice(0, MAX_FILAS).map((fila) => {
        const valores = d.campos.map((campo, k) => valorDeCampo(campo, Array.isArray(fila && fila.valores) ? fila.valores[k] : null));
        return { valores, obs: texto(fila && fila.obs, 500) || null };
    }).filter((fila) => fila.valores.some((v) => v !== null) || fila.obs);
    return { id: formulario.id, nombre: formulario.nombre, definicion: d, filas, observacion, contestadas: filas.length };
}

// Vencimientos que salen de una planilla (por ejemplo "Vencimiento carga" de cada extintor).
function vencimientosDe(resultado) {
    const d = resultado.definicion;
    if (d.tipo === 'excel') {
        // Cada fecha cargada en una columna de "vencimiento", con los datos de su fila para reconocerla.
        const salida = [];
        for (const campo of d.campos) {
            const valor = resultado.valores[`${campo.f},${campo.c}`];
            if (campo.tipo !== 'fecha' || !valor || !/venc/i.test(campo.encabezado || '')) continue;
            const deLaFila = d.campos
                .filter((otro) => otro.f === campo.f && otro.tipo === 'texto' && resultado.valores[`${otro.f},${otro.c}`])
                .slice(0, 3)
                .map((otro) => resultado.valores[`${otro.f},${otro.c}`]);
            salida.push({
                clave: `${campo.f}-${campo.c}`,
                descripcion: `${resultado.nombre}: ${deLaFila.join(' · ') || `fila ${campo.f + 1}`} — ${campo.encabezado}`.slice(0, 300),
                vence: valor,
            });
        }
        return salida;
    }
    if (d.tipo !== 'planilla') return [];
    const salida = [];
    resultado.filas.forEach((fila, i) => {
        const nombreFila = [fila.valores[0], ...d.campos.slice(1).map((campo, k) => (/^n[º°]|tipo|capacidad/i.test(campo.etiqueta) && fila.valores[k + 1] !== null ? `${campo.etiqueta} ${fila.valores[k + 1]}` : null))]
            .filter((v) => v !== null && v !== '').join(' · ');
        d.campos.forEach((campo, k) => {
            if (campo.tipo === 'fecha' && /venc/i.test(campo.etiqueta) && fila.valores[k]) {
                salida.push({ clave: `${i}-${k}`, descripcion: `${d.elemento || 'Elemento'} ${nombreFila || i + 1} — ${campo.etiqueta}`.slice(0, 300), vence: fila.valores[k] });
            }
        });
    });
    return salida;
}

// =====================================================================
// RUTAS
// =====================================================================
function registrarRutasFormularios(app, { pool, usuarioDelPanel }) {
    const presentar = (fila) => ({ id: fila.id, nombre: fila.nombre, archivo: fila.archivo || null, definicion: definicionDe(fila), puntos: fila.puntos || [] });

    app.get('/api/formularios', usuarioDelPanel, async (req, res) => {
        try {
            const filas = await pool.query('SELECT id, nombre, puntos, definicion, archivo FROM formularios_visita WHERE activo = true ORDER BY lower(nombre)');
            res.json(filas.rows.map(presentar));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudieron leer los formularios' });
        }
    });

    // Convierte un Excel en un formulario y lo devuelve para revisarlo. Todavía no se guarda nada.
    app.post('/api/formularios/importar', usuarioDelPanel, (req, res) => {
        const archivo = texto(req.body && req.body.archivo, 200) || 'Formulario.xls';
        const crudo = String((req.body && req.body.contenido) || '');
        const base64 = crudo.includes(',') ? crudo.slice(crudo.indexOf(',') + 1) : crudo;
        const buffer = Buffer.from(base64, 'base64');
        if (!buffer.length) return res.status(400).json({ error: 'El archivo está vacío' });
        if (buffer.length > MAX_ARCHIVO) return res.status(400).json({ error: 'El archivo es muy grande (máximo 6 MB)' });
        try {
            res.json({ archivo, ...convertirExcel(buffer, archivo) });
        } catch (error) {
            res.status(400).json({ error: error.message && error.message.length < 120 ? error.message : 'No se pudo leer el Excel' });
        }
    });

    app.post('/api/formularios', usuarioDelPanel, async (req, res) => {
        const cuerpo = req.body || {};
        const nombre = texto(cuerpo.nombre, 80);
        if (!nombre) return res.status(400).json({ error: 'Poné un nombre al formulario' });
        // Forma vieja: solo una lista de puntos.
        const entrada = cuerpo.definicion || (Array.isArray(cuerpo.puntos) ? { tipo: 'lista', opciones: ['SI', 'NO', 'NC'], preguntas: cuerpo.puntos } : null);
        if (!entrada && Array.isArray(cuerpo.puntos)) return res.status(400).json({ error: 'Agregá al menos un punto, uno por renglón' });
        const limpia = limpiarDefinicion(entrada);
        if (limpia.error) return res.status(400).json({ error: Array.isArray(cuerpo.puntos) ? 'Agregá al menos un punto, uno por renglón' : limpia.error });
        const puntos = limpia.definicion.tipo === 'lista' ? limpia.definicion.preguntas.filter((p) => !p.seccion).map((p) => p.texto) : [];
        try {
            const nuevo = await pool.query(
                'INSERT INTO formularios_visita (nombre, puntos, definicion, archivo) VALUES ($1, $2::jsonb, $3::jsonb, $4) RETURNING id, nombre, puntos, definicion, archivo',
                [nombre, JSON.stringify(puntos), JSON.stringify(limpia.definicion), texto(cuerpo.archivo, 200) || null]
            );
            res.json(presentar(nuevo.rows[0]));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar el formulario' });
        }
    });

    app.put('/api/formularios/:id', usuarioDelPanel, async (req, res) => {
        const id = Number(req.params.id);
        if (!Number.isInteger(id)) return res.status(400).json({ error: 'Formulario inválido' });
        const nombre = texto(req.body && req.body.nombre, 80);
        if (!nombre) return res.status(400).json({ error: 'Poné un nombre al formulario' });
        const limpia = limpiarDefinicion(req.body && req.body.definicion);
        if (limpia.error) return res.status(400).json({ error: limpia.error });
        const puntos = limpia.definicion.tipo === 'lista' ? limpia.definicion.preguntas.filter((p) => !p.seccion).map((p) => p.texto) : [];
        try {
            const cambio = await pool.query(
                'UPDATE formularios_visita SET nombre = $1, definicion = $2::jsonb, puntos = $3::jsonb WHERE id = $4 AND activo = true RETURNING id, nombre, puntos, definicion, archivo',
                [nombre, JSON.stringify(limpia.definicion), JSON.stringify(puntos), id]
            );
            if (!cambio.rows[0]) return res.status(404).json({ error: 'Ese formulario no existe' });
            res.json(presentar(cambio.rows[0]));
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'No se pudo guardar el formulario' });
        }
    });

    app.delete('/api/formularios/:id', usuarioDelPanel, async (req, res) => {
        try {
            await pool.query('UPDATE formularios_visita SET activo = false WHERE id = $1', [req.params.id]);
            res.json({ ok: true });
        } catch (error) {
            res.status(500).json({ error: 'No se pudo borrar el formulario' });
        }
    });
}

module.exports = {
    registrarRutasFormularios, convertirExcel, convertirHoja, limpiarDefinicion, copiaDeFormularios, formulariosFijosDe,
    normalizarRespuestas, vencimientosDe, definicionDe,
};
