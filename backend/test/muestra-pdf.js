// Genera un informe de ejemplo para revisar el diseño del PDF a simple vista.
// Uso:  node test/muestra-pdf.js [largo]      (con "largo" arma un informe de varias hojas)
const fs = require('fs');
const path = require('path');
const { crearInforme } = require('../src/pdf');

const imagen = (nombre) => `data:image/png;base64,${fs.readFileSync(path.join(__dirname, '..', nombre)).toString('base64')}`;
const largo = process.argv[2] === 'largo';
const destino = path.join(__dirname, largo ? 'muestra-informe-largo.pdf' : 'muestra-informe.pdf');

const tareas = [
    'Revisión general de extintores y fechas de carga',
    'Verificar señalética de salidas de emergencia y su iluminación',
    'Medición de iluminación en puestos de trabajo',
    'Controlar botiquines de primeros auxilios',
    'Registrar evidencias fotográficas',
];
const muchas = Array.from({ length: 30 }, (_, i) => `Tarea de control número ${i + 1} con una descripción un poco más larga para ver cómo se parte el renglón`);

crearInforme({
    destino,
    cliente: 'Clínica del Sol S.A.',
    tecnico: 'María Claudia Fernández',
    direccion: 'Av. Colón 1234, Córdoba, Córdoba',
    comentarios: largo
        ? Array.from({ length: 14 }, () => 'Se realizó la visita según lo programado. El cliente recibió la documentación y se acordó una nueva visita de control.').join('\n\n')
        : 'Se realizó la visita según lo programado. Se encontraron dos extintores vencidos que fueron informados al responsable del establecimiento.',
    latitud: -31.42008,
    longitud: -64.18877,
    firmaTecnico: imagen('temp_tecnico.png'),
    firmaCliente: imagen('temp_cliente.png'),
    evidencias: largo ? [1, 2, 3, 4, 5].map(() => imagen('temp_foto_0.png')) : [imagen('temp_foto_0.png'), imagen('temp_foto_0.png')],
    checklist: (largo ? muchas : tareas).map((tarea, i) => ({ tarea, hecho: i % 3 !== 2 })),
    inicio: '2026-10-27T13:05:00.000Z',
    fin: '2026-10-27T14:50:00.000Z',
}).then(() => console.log(`Listo: ${destino}`)).catch((error) => { console.error(error); process.exit(1); });
