// Ubica tres lugares reales de Córdoba y comprueba que la recorrida no arranca por el del medio.
// Si el mapa no responde, no falla: lo avisa y sale bien.
require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
    user: process.env.DB_USER, host: process.env.DB_HOST, database: process.env.DB_NAME,
    password: process.env.DB_PASSWORD, port: Number(process.env.DB_PORT || 5432),
});
const { ordenarRecorrido } = require('../src/ruta');

(async () => {
    const marca = Date.now();
    const cliente = `Ruta prueba ${marca}`;
    const lugares = [
        ['Patio Olmos, Córdoba', 'patio'],
        ['Aeropuerto Internacional de Córdoba, Argentina', 'aeropuerto'],
        ['Plaza San Martín, Córdoba', 'plaza'],
    ];
    let tecnicoId = null;
    const ids = [];
    try {
        const tec = await pool.query('SELECT id FROM tecnicos WHERE activo = TRUE ORDER BY id LIMIT 1');
        tecnicoId = tec.rows[0] && tec.rows[0].id;
        if (!tecnicoId) {
            console.log('Sin técnico: no se probó el mapa');
            return;
        }
        const empresa = await pool.query(
            'INSERT INTO empresas (razon_social, direccion_principal) VALUES ($1, $2) RETURNING id',
            [cliente, 'Córdoba']
        );
        for (const [direccion] of lugares) {
            const nueva = await pool.query(
                `INSERT INTO ordenes (tecnico_id, empresa_id, direccion_trabajo, descripcion_tarea, fecha_asignada, estado, fecha_ocurrencia)
                 VALUES ($1, $2, $3, 'prueba', '2099-01-15', 'Pendiente', '2099-01-15') RETURNING id`,
                [tecnicoId, empresa.rows[0].id, `${direccion} ${marca}`]
            );
            ids.push(nueva.rows[0].id);
        }
        // La marca al final haría imposible ubicarlas. Se guardan las direcciones limpias.
        for (let i = 0; i < ids.length; i++) {
            await pool.query('UPDATE ordenes SET direccion_trabajo = $1 WHERE id = $2', [lugares[i][0], ids[i]]);
        }
        await ordenarRecorrido(pool, tecnicoId, '2099-01-15');
        const filas = await pool.query(
            'SELECT id, direccion_trabajo, orden_ruta, lat FROM ordenes WHERE id = ANY($1) ORDER BY orden_ruta NULLS LAST',
            [ids]
        );
        const ubicadas = filas.rows.filter((fila) => fila.lat != null);
        if (ubicadas.length < 3) {
            console.log('El mapa no ubicó las tres direcciones. La recorrida queda para cuando responda.');
            console.log(filas.rows.map((fila) => `${fila.direccion_trabajo} -> ${fila.orden_ruta}`).join(' | '));
            return;
        }
        const medio = filas.rows[1].direccion_trabajo;
        const extremo = !/aeropuerto/i.test(filas.rows[1].direccion_trabajo);
        console.log(filas.rows.map((fila) => `${fila.orden_ruta}. ${fila.direccion_trabajo}`).join(' | '));
        if (!extremo) {
            console.log('FALLA: el aeropuerto quedó en el medio de la recorrida');
            process.exitCode = 1;
        } else {
            console.log('OK   El aeropuerto no quedó entre las dos paradas del centro');
        }
        if (medio && filas.rows.some((fila) => fila.orden_ruta == null)) {
            console.log('FALLA: falta el número de parada');
            process.exitCode = 1;
        }
    } catch (error) {
        console.log('No se pudo probar el mapa:', error.message);
    } finally {
        if (ids.length) await pool.query('DELETE FROM ordenes WHERE id = ANY($1)', [ids]);
        await pool.query('DELETE FROM empresas WHERE razon_social = $1', [cliente]);
        await pool.end();
    }
})();
