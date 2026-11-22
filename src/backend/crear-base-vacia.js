// Crea la base son_vacia si todavía no existe. No toca sima_db.
require('dotenv').config();
const { Client } = require('pg');

const NOMBRE = 'son_vacia';

async function main() {
    const admin = new Client({
        user: process.env.DB_USER,
        host: process.env.DB_HOST,
        database: 'postgres',
        password: process.env.DB_PASSWORD,
        port: Number(process.env.DB_PORT || 5432),
    });
    await admin.connect();
    const existe = await admin.query('SELECT 1 FROM pg_database WHERE datname = $1', [NOMBRE]);
    if (existe.rowCount) {
        console.log(`La base ${NOMBRE} ya existe.`);
    } else {
        await admin.query(`CREATE DATABASE ${NOMBRE}`);
        console.log(`Base ${NOMBRE} creada.`);
    }
    await admin.end();
}

main().catch((error) => {
    console.error(error.message);
    process.exit(1);
});
