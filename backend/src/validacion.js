// Ayudas para revisar lo que llega en los pedidos. Cada una devuelve el valor limpio o un { error } con
// un mensaje que se le puede mostrar a la persona.

function vacio(valor) {
    return valor === undefined || valor === null || (typeof valor === 'string' && valor.trim() === '');
}

// "12" o 12 -> 12. Cualquier otra cosa (vacío, "abc", 1.5) da NaN.
function parseEntero(valor) {
    if (typeof valor === 'number') return Number.isInteger(valor) ? valor : NaN;
    if (typeof valor === 'string' && /^\d{1,9}$/.test(valor.trim())) return Number(valor.trim());
    return NaN;
}

// 12, "12", "12.5" o "12,5" -> número. Cualquier otra cosa da NaN.
function parseNumero(valor) {
    if (typeof valor === 'number') return Number.isFinite(valor) ? valor : NaN;
    if (typeof valor === 'string') {
        const texto = valor.trim().replace(',', '.');
        if (/^-?\d+(\.\d+)?$/.test(texto)) return Number(texto);
    }
    return NaN;
}

function textoOpcional(valor, maximo, etiqueta) {
    const texto = String(valor ?? '').trim();
    if (texto.length > maximo) return { error: `${etiqueta} es demasiado largo (máximo ${maximo} letras)` };
    return { texto: texto || null };
}

function textoRequerido(valor, maximo, etiqueta) {
    const texto = String(valor ?? '').trim();
    if (!texto) return { error: `Completá ${etiqueta.toLowerCase()}` };
    if (texto.length > maximo) return { error: `${etiqueta} es demasiado largo (máximo ${maximo} letras)` };
    return { texto };
}

// Número opcional dentro de un rango. Vacío da { numero: null }.
function numeroOpcional(valor, { minimo = 0, maximo = 1e11, etiqueta = 'El valor' } = {}) {
    if (vacio(valor)) return { numero: null };
    const numero = parseNumero(valor);
    if (Number.isNaN(numero)) return { error: `${etiqueta} tiene que ser un número` };
    if (numero < minimo || numero > maximo) return { error: `${etiqueta} tiene que estar entre ${minimo} y ${maximo}` };
    return { numero };
}

// true / false (también "true", "false", 1, 0). Si no viene, se usa el valor por defecto.
function booleano(valor, porDefecto) {
    if (valor === undefined || valor === null || valor === '') return porDefecto;
    if (valor === true || valor === 'true' || valor === 1 || valor === '1') return true;
    if (valor === false || valor === 'false' || valor === 0 || valor === '0') return false;
    return porDefecto;
}

// "AAAA-MM-DD" que sea una fecha real.
function fechaValida(texto) {
    if (typeof texto !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(texto)) return false;
    const [anio, mes, dia] = texto.split('-').map(Number);
    const fecha = new Date(Date.UTC(anio, mes - 1, dia));
    return fecha.getUTCFullYear() === anio && fecha.getUTCMonth() === mes - 1 && fecha.getUTCDate() === dia;
}

module.exports = { vacio, parseEntero, parseNumero, textoOpcional, textoRequerido, numeroOpcional, booleano, fechaValida };
