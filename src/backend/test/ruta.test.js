// El orden de la recorrida no necesita base de datos ni internet.
const { mejorRecorrido, mejorDesdeSalida, elegirLugar, ordenDesdeViaje } = require('../src/ruta');

let fallos = 0;
function paso(nombre, ok) {
    if (!ok) fallos++;
    console.log(`${ok ? 'OK   ' : 'FALLA'} ${nombre}`);
}

// Tres puntos en línea: el camino corto es oeste -> centro -> este, no empezar por el centro.
const oeste = { id: 1, lat: -31.4, lng: -64.3 };
const centro = { id: 2, lat: -31.4, lng: -64.2 };
const este = { id: 3, lat: -31.4, lng: -64.1 };
const orden = mejorRecorrido([centro, este, oeste]);
paso('Elige un extremo como salida para no ir y volver', orden[0] !== 2 && orden[1] === 2);
paso('Una sola parada queda primera', mejorRecorrido([{ id: 9, lat: 1, lng: 1 }]).join() === '9');
paso('Sin paradas no arma nada', mejorRecorrido([]).length === 0);

const viaje = ordenDesdeViaje([10, 20, 30], [{ waypoint_index: 2 }, { waypoint_index: 0 }, { waypoint_index: 1 }]);
paso('Respeta el orden que devuelve el mapa de calles', viaje.join() === '20,30,10');
paso('Si el mapa responde mal, no inventa un orden', ordenDesdeViaje([1], []) === null);

const base = { lat: -31.66, lng: -64.43 };
const superAltaGracia = { id: 1, lat: -31.65, lng: -64.44 };
const plazaCordoba = { id: 2, lat: -31.43, lng: -64.18 };
paso('Sale de Alta Gracia y deja Córdoba para el final', mejorDesdeSalida(base, [plazaCordoba, superAltaGracia]).join() === '1,2');

const lugar = elegirLugar('Supermercado beccera central', base, [
    { lat: 10.45, lng: -66.87, nombre: 'Supermercado Central', provincia: 'Miranda' },
    { lat: -32.06, lng: -64.54, nombre: 'Supermercado Becerra', provincia: 'Córdoba' },
    { lat: -31.65, lng: -64.44, nombre: 'Supermercados Becerra', provincia: 'Córdoba' },
]);
paso('Con un error de tipeo elige el Becerra de Alta Gracia', lugar && Math.abs(lugar.lat - (-31.65)) < 0.01);

console.log(fallos ? `RESULTADO: ${fallos} fallas` : 'RESULTADO: todo OK');
process.exit(fallos ? 1 : 0);
