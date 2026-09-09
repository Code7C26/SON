const express = require('express');
const cors = require('cors');
const PDFDocument = require('pdfkit'); 
const fs = require('fs'); 
const { Pool } = require('pg'); // <-- Importamos el conector de PostgreSQL

const app = express();

app.use(cors());
app.use(express.json({ limit: '50mb' }));

// --- CONEXIÓN A LA BASE DE DATOS ---
const pool = new Pool({
    user: 'postgres',
    host: 'localhost',
    database: 'sima_db',
    password: 'SON2026', 
    port: 5432,
});

pool.connect()
    .then(() => console.log('¡Conectado exitosamente a la Base de Datos PostgreSQL!'))
    .catch(err => console.error('Error conectando a PostgreSQL:', err));

// --- RUTAS ---

// Obtener órdenes reales desde la Base de Datos
app.get('/api/ordenes', async (req, res) => {
    try {
        // Buscamos las órdenes y unimos la tabla empresas para obtener la razón social
        const consulta = `
            SELECT o.id, o.descripcion_tarea as tarea, e.razon_social as cliente, o.direccion_trabajo as direccion, o.estado
            FROM ordenes o
            JOIN empresas e ON o.empresa_id = e.id
        `;
        const resultado = await pool.query(consulta);
        res.json(resultado.rows);
    } catch (error) {
        console.error('Error al obtener órdenes:', error);
        res.status(500).json({ error: 'Error del servidor' });
    }
});
// --- RUTAS DE TÉCNICOS ---

// Obtener la lista de técnicos
app.get('/api/tecnicos', async (req, res) => {
    try {
        const resultado = await pool.query('SELECT id, nombre, email, activo FROM tecnicos ORDER BY id ASC');
        res.json(resultado.rows);
    } catch (error) {
        console.error('Error al obtener técnicos:', error);
        res.status(500).json({ error: 'Error del servidor' });
    }
});

// Registrar un nuevo técnico
app.post('/api/tecnicos', async (req, res) => {
    const { nombre, email, password } = req.body;
    try {
        const resultado = await pool.query(
            'INSERT INTO tecnicos (nombre, email, password) VALUES ($1, $2, $3) RETURNING id, nombre, email',
            [nombre, email, password]
        );
        res.json(resultado.rows[0]);
    } catch (error) {
        console.error('Error al registrar técnico:', error);
        res.status(500).json({ error: 'Error al registrar el técnico' });
    }
});
// ... (Aquí debe continuar intacto tu app.post('/api/generar-informe', ... )
app.post('/api/generar-informe', (req, res) => {
    const { cliente, direccion, comentarios, latitud, longitud, firmaTecnico, firmaCliente, evidencias } = req.body;

    const doc = new PDFDocument({ margin: 50 });
    res.setHeader('Content-Type', 'application/pdf');
    
    const nombreArchivo = `Informe_${(cliente || 'Sin_Nombre').replace(/\s+/g, '_')}.pdf`;
    doc.pipe(res);
    doc.pipe(fs.createWriteStream(nombreArchivo));

    // --- NUEVO MEMBRETE (Solo la imagen, sin fondo verde) ---
    if (fs.existsSync('LOGO_PDF.png')) {
        doc.image('LOGO_PDF.png', 50, 20, { width: 250 }); 
    }
    
    // Bajamos el cursor para empezar el título debajo de la imagen
    doc.y = 100;

    doc.fillColor('#003024').fontSize(18).text('INFORME DE VISITA', { align: 'center', underline: true });
    doc.moveDown(2);

    doc.fontSize(12).fillColor('black');
    doc.text(`Empresa: ${cliente}`);
    doc.text(`Planta / Local: Sede Principal`);
    doc.text(`Fecha: ${new Date().toLocaleDateString()}`);
    doc.text(`Dirección: ${direccion}`);
    doc.text(`Ubicación GPS Check-in: Lat ${latitud}, Lng ${longitud}`);
    doc.moveDown(1.5);

    doc.fontSize(14).fillColor('#003024').text('Comentarios y Observaciones:');
    doc.fontSize(12).fillColor('black').text(comentarios || 'Sin observaciones adicionales.');
    doc.moveDown(2);

    doc.fontSize(14).fillColor('#003024').text('Registros Fotográficos:');
    doc.moveDown(0.5);

    if (evidencias && evidencias.length > 0) {
        let imgX = 50;
        let imgY = doc.y;
        let imgWidth = 110;
        let imgHeight = 110;
        let spacing = 15;

        evidencias.forEach((fotoBase64, index) => {
            try {
                if (fotoBase64 && fotoBase64.includes(',')) {
                    const base64Data = fotoBase64.split(',')[1];
                    const bufferFoto = Buffer.from(base64Data, 'base64');
                    const tempPath = `temp_foto_${index}.png`;
                    fs.writeFileSync(tempPath, bufferFoto);

                    if (imgX + imgWidth > 550) {
                        imgX = 50;
                        imgY += imgHeight + spacing;
                    }

                    doc.image(tempPath, imgX, imgY, { width: imgWidth, height: imgHeight });
                    imgX += imgWidth + spacing;
                }
            } catch (e) {
                console.log(`Error al procesar foto ${index}:`, e);
            }
        });
        doc.y = imgY + imgHeight + 25;
    } else {
        doc.fontSize(10).fillColor('grey').text('Sin registros fotográficos adjuntos.');
        doc.moveDown(2);
    }

    doc.fontSize(14).fillColor('#003024').text('Firmas de Conformidad:');
    doc.moveDown(1);

    let currentY = doc.y;

    // --- FIRMAS CORREGIDAS (Uso de 'fit' para mantener proporciones reales) ---
    if (firmaTecnico && firmaTecnico.includes(',')) {
        try {
            const base64Data = firmaTecnico.split(',')[1];
            const bufferTecnico = Buffer.from(base64Data, 'base64');
            fs.writeFileSync('temp_tecnico.png', bufferTecnico);
            doc.image('temp_tecnico.png', 50, currentY, { fit: [180, 80] });
        } catch (e) {
            console.log('Error al procesar firma técnico:', e);
        }
    }

    if (firmaCliente && firmaCliente.includes(',')) {
        try {
            const base64Data = firmaCliente.split(',')[1];
            const bufferCliente = Buffer.from(base64Data, 'base64');
            fs.writeFileSync('temp_cliente.png', bufferCliente);
            doc.image('temp_cliente.png', 320, currentY, { fit: [180, 80] });
        } catch (e) {
            console.log('Error al procesar firma cliente:', e);
        }
    }

    doc.fontSize(10).fillColor('black');
    doc.text('Firma del Técnico', 50, currentY + 90);
    doc.text('Firma del Cliente', 320, currentY + 90);
    doc.moveDown(3);

    doc.moveTo(50, doc.y).lineTo(562, doc.y).stroke('#dddddd');
    doc.moveDown(1);
    doc.fontSize(11).fillColor('#003024');
    doc.text('Confeccionó: Juan Pérez (Técnico Operativo)', 50, doc.y);
    doc.text('Aprobó: Directorio / Operaciones Sima', 50, doc.y + 18);

    doc.end();
});

app.listen(3000, () => {
    console.log('Servidor corriendo en http://localhost:3000');
});