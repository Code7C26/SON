const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const PDFDocument = require('pdfkit'); 
const fs = require('fs'); 
const path = require('path');

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' })); // Límite alto para soportar las fotos en Base64

const pool = new Pool({
    user: 'postgres',
    host: 'localhost',
    database: 'sima_db',
    password: 'SON2026', // <--- CAMBIA ESTO
    port: 5432,
});

pool.connect()
    .then(() => console.log('¡Conectado exitosamente a PostgreSQL!'))
    .catch(err => console.error('Error de conexión a la base de datos', err.stack));

// ==========================================
// 1. RUTAS DE TÉCNICOS
// ==========================================
app.get('/api/tecnicos', async (req, res) => {
    try {
        const resultado = await pool.query('SELECT id, nombre, email, activo FROM tecnicos ORDER BY id ASC');
        res.json(resultado.rows);
    } catch (error) {
        res.status(500).json({ error: 'Error del servidor' });
    }
});
// ==========================================
// RUTAS EXCLUSIVAS PARA LA APP MÓVIL (TÉCNICOS)
// ==========================================

// 1. Login de la App Móvil
app.post('/api/tecnicos/login', async (req, res) => {
    let { email, password } = req.body;
    
    // Limpiamos espacios accidentales
    email = email ? email.trim() : '';
    password = password ? password.trim() : '';

    try {
        const resultado = await pool.query(
            'SELECT id, nombre, email FROM tecnicos WHERE email = $1 AND password = $2 AND activo = TRUE',
            [email, password]
        );
        
        if (resultado.rows.length > 0) {
            res.json(resultado.rows[0]); // Devuelve los datos del técnico (id, nombre, email)
        } else {
            res.status(401).json({ error: 'Correo o contraseña incorrectos' });
        }
    } catch (error) {
        console.error('Error en el login de técnico:', error);
        res.status(500).json({ error: 'Error interno del servidor' });
    }
});

// 2. Obtener "Mis Órdenes" (Solo las asignadas al técnico logueado)
app.get('/api/ordenes/tecnico/:id', async (req, res) => {
    const { id } = req.params;
    try {
        const resultado = await pool.query(`
            SELECT o.id, o.direccion_trabajo as direccion, o.descripcion_tarea as tarea, o.estado, e.razon_social as cliente 
            FROM ordenes o 
            LEFT JOIN empresas e ON o.empresa_id = e.id 
            WHERE o.tecnico_id = $1
            ORDER BY o.id DESC
        `, [id]);
        res.json(resultado.rows);
    } catch (error) {
        console.error('Error al obtener órdenes del técnico:', error);
        res.status(500).json({ error: 'Error del servidor' });
    }
});

app.post('/api/tecnicos', async (req, res) => {
    const { nombre, email, password } = req.body;
    try {
        const resultado = await pool.query(
            'INSERT INTO tecnicos (nombre, email, password) VALUES ($1, $2, $3) RETURNING id, nombre, email',
            [nombre, email, password]
        );
        res.json(resultado.rows[0]);
    } catch (error) {
        res.status(500).json({ error: 'Error al registrar el técnico' });
    }
});

// ==========================================
// 2. RUTAS DE ÓRDENES (Con Recurrencia Google)
// ==========================================
app.get('/api/ordenes', async (req, res) => {
    try {
        const resultado = await pool.query(`
            SELECT o.*, e.razon_social as cliente 
            FROM ordenes o 
            LEFT JOIN empresas e ON o.empresa_id = e.id 
            ORDER BY o.id DESC
        `);
        res.json(resultado.rows);
    } catch (error) {
        res.status(500).json({ error: 'Error del servidor' });
    }
});

app.post('/api/ordenes', async (req, res) => {
    const { 
        tecnico_id, nombre_cliente, direccion_trabajo, descripcion_tarea, 
        es_recurrente, recurrencia_valor, recurrencia_tipo, hora_ejecucion, 
        termina_condicion, termina_fecha, termina_repeticiones 
    } = req.body;
    
    try {
        let empresa_id;
        const busqueda = await pool.query('SELECT id FROM empresas WHERE razon_social = $1', [nombre_cliente]);
        
        if (busqueda.rows.length > 0) {
            empresa_id = busqueda.rows[0].id;
        } else {
            const carpeta = nombre_cliente.replace(/\s+/g, '_'); 
            const nuevaEmpresa = await pool.query(
                'INSERT INTO empresas (razon_social, direccion_principal, carpeta_disco_k) VALUES ($1, $2, $3) RETURNING id',
                [nombre_cliente, direccion_trabajo, carpeta]
            );
            empresa_id = nuevaEmpresa.rows[0].id;
        }

        const nuevaOrden = await pool.query(
            `INSERT INTO ordenes (tecnico_id, empresa_id, direccion_trabajo, descripcion_tarea, fecha_asignada, estado, 
                es_recurrente, recurrencia_valor, recurrencia_tipo, hora_ejecucion, termina_condicion, termina_fecha, termina_repeticiones) 
             VALUES ($1, $2, $3, $4, CURRENT_DATE, 'Pendiente', $5, $6, $7, $8, $9, $10, $11) RETURNING *`,
            [tecnico_id, empresa_id, direccion_trabajo, descripcion_tarea, es_recurrente || false, recurrencia_valor || 1, recurrencia_tipo || 'día', hora_ejecucion || '12:30', termina_condicion || 'Nunca', termina_fecha || null, termina_repeticiones || 30]
        );
        res.json(nuevaOrden.rows[0]);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error al crear orden' });
    }
});

app.put('/api/ordenes/:id', async (req, res) => {
    const { id } = req.params;
    const { direccion_trabajo, descripcion_tarea } = req.body;
    try {
        await pool.query('UPDATE ordenes SET direccion_trabajo = $1, descripcion_tarea = $2 WHERE id = $3', [direccion_trabajo, descripcion_tarea, id]);
        res.json({ mensaje: 'Actualizada' });
    } catch (error) {
        res.status(500).json({ error: 'Error' });
    }
});

app.delete('/api/ordenes/:id', async (req, res) => {
    try {
        await pool.query('DELETE FROM ordenes WHERE id = $1', [req.params.id]);
        res.json({ mensaje: 'Eliminada' });
    } catch (error) {
        res.status(500).json({ error: 'Error' });
    }
});

// ==========================================
// 3. RUTAS DE INFORMES (DISCO K)
// ==========================================
const RUTA_BASE_DISCO_K = 'K:\\SIMA_Informes'; // <-- ASEGÚRATE DE QUE ESTA LETRA EXISTA EN TU PC

// Generar PDF y guardarlo en el Disco K
app.post('/api/generar-informe', (req, res) => {
    const { cliente, direccion, comentarios, latitud, longitud, firmaTecnico, firmaCliente, evidencias } = req.body;

    const doc = new PDFDocument({ margin: 50 });
    res.setHeader('Content-Type', 'application/pdf');
    
    const nombreCarpeta = (cliente || 'Sin_Nombre').replace(/\s+/g, '_');
    const rutaDirectorioCliente = path.join(RUTA_BASE_DISCO_K, nombreCarpeta);

    // Si la carpeta del cliente no existe en el disco K, se crea automáticamente
    if (!fs.existsSync(rutaDirectorioCliente)) {
        fs.mkdirSync(rutaDirectorioCliente, { recursive: true });
    }

    const nombreArchivo = `Informe_${nombreCarpeta}_${Date.now()}.pdf`;
    const rutaCompletaPDF = path.join(rutaDirectorioCliente, nombreArchivo);

    doc.pipe(res);
    doc.pipe(fs.createWriteStream(rutaCompletaPDF));

    // Cabecera limpia
    if (fs.existsSync('LOGO_PDF.jpg')) {
        doc.image('LOGO_PDF.jpg', 0, 0, { width: 612 }); 
        doc.moveDown(5);
    } else {
        doc.fontSize(20).text('SIMA OPERATION', { align: 'center' });
        doc.moveDown(2);
    }

    // Datos
    doc.fontSize(18).text('INFORME DE VISITA', { align: 'center', underline: true });
    doc.moveDown(1.5);
    doc.fontSize(12).text(`Empresa: ${cliente || 'N/A'}`);
    doc.text(`Fecha: ${new Date().toLocaleDateString()}`);
    doc.text(`Dirección: ${direccion || 'N/A'}`);
    doc.moveDown(1.5);
    doc.fontSize(14).text('Comentarios:', { underline: true });
    doc.fontSize(12).text(comentarios || 'Sin observaciones.');
    
    // (AQUÍ IRÍAN LAS FOTOS Y FIRMAS EXACTAMENTE COMO LAS TENÍAS ANTES)
    
    doc.end();
});

// NUEVA RUTA: Leer el Disco K para enviarle a Flutter las carpetas reales
app.get('/api/informes/carpetas', (req, res) => {
    try {
        if (!fs.existsSync(RUTA_BASE_DISCO_K)) {
            return res.json([]); 
        }
        
        // Lee las carpetas y cuenta cuántos PDF tiene cada una adentro
        const carpetas = fs.readdirSync(RUTA_BASE_DISCO_K, { withFileTypes: true })
            .filter(dirent => dirent.isDirectory())
            .map(dirent => {
                const rutaCarpeta = path.join(RUTA_BASE_DISCO_K, dirent.name);
                const cantidadArchivos = fs.readdirSync(rutaCarpeta).filter(f => f.endsWith('.pdf')).length;
                return { 
                    empresa: dirent.name.replace(/_/g, ' '), 
                    cantidad: cantidadArchivos 
                };
            });
            
        res.json(carpetas);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'No se pudo leer el disco' });
    }
});
// ==========================================
// 0. RUTAS DE LOGIN (ADMINISTRADOR)
// ==========================================
app.post('/api/admin/login', (req, res) => {
    const { email, password } = req.body;
    
    // Aquí validamos el usuario y contraseña
    // (Puse 123456 por los 6 puntos de tu captura, cámbialo si usabas otra clave)
    if (email === 'admin@son.com' && password === '123456') { 
        res.json({ mensaje: 'Login exitoso', token: 'token-admin-sima' });
    } else {
        res.status(401).json({ error: 'Credenciales incorrectas' });
    }
});
// ==========================================
// 4. INICIAR SERVIDOR
// ==========================================
app.listen(3000, '0.0.0.0', () => {
    console.log('Servidor corriendo en el puerto 3000 (Modo Universal)');
});