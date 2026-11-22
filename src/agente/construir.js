// Arma SON-Agente.exe: un solo archivo que NO necesita tener Node instalado.
// Uso (en una PC con Node 20 o más nuevo):   node construir.js
// Resultado: agente/dist/SON-Agente.exe y una copia en backend/descargas/ (desde ahí lo baja el panel).
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const dist = path.join(__dirname, 'dist');
const exe = path.join(dist, 'SON-Agente.exe');
const blob = path.join(dist, 'sea-prep.blob');
const configSea = path.join(dist, 'sea-config.json');

fs.rmSync(dist, { recursive: true, force: true });
fs.mkdirSync(dist, { recursive: true });
fs.writeFileSync(configSea, JSON.stringify({
    main: path.join(__dirname, 'agente.js'),
    output: blob,
    disableExperimentalSEAWarning: true,
}));

console.log('1/3 Empaquetando el código...');
execFileSync(process.execPath, ['--experimental-sea-config', configSea], { stdio: 'inherit' });

console.log('2/3 Copiando el motor de Node...');
fs.copyFileSync(process.execPath, exe);

console.log('3/3 Inyectando el agente en el programa...');
const comando = process.platform === 'win32' ? 'npx.cmd' : 'npx';
execFileSync(comando, [
    '--yes', 'postject', exe, 'NODE_SEA_BLOB', blob,
    '--sentinel-fuse', 'NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2',
], { stdio: 'inherit', shell: process.platform === 'win32' });

const descargas = path.join(__dirname, '..', 'backend', 'descargas');
fs.mkdirSync(descargas, { recursive: true });
fs.copyFileSync(exe, path.join(descargas, 'SON-Agente.exe'));
const mb = (fs.statSync(exe).size / 1024 / 1024).toFixed(0);
console.log(`\nListo: ${exe} (${mb} MB)\nCopia para el panel: ${path.join(descargas, 'SON-Agente.exe')}`);
