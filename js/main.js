import { route, render } from './router.js';
import { sincronizar } from './services/storage.js';
import { cargarSesion } from './services/sesion.js';
import './controllers/usuario.js';            // botón de perfil: iniciar sesión / mi cuenta
import { icon } from './views/icons.js';
import { getEspecies } from './services/api.js';
import camara from './controllers/camara.js';
import mapa from './controllers/mapa.js';
import buscar from './controllers/buscar.js';
import ficha from './controllers/ficha.js';
import revisar from './controllers/revisar.js';

document.getElementById('nav').innerHTML =
  `<a href="#/mapa" data-r="mapa">${icon('map', 24)}Mapa</a>
   <a href="#/camara" data-r="camara" class="mid"><i class="sp"></i>Cámara<b>${icon('camera', 26)}</b></a>
   <a href="#/buscar" data-r="buscar">${icon('search', 24)}Buscar</a>
   <a href="#/revisar" data-r="revisar" class="solo-bio rev">${icon('verified', 24)}Revisar<span class="nbadge" hidden></span></a>`;

document.getElementById('hrev').insertAdjacentHTML('afterbegin', icon('verified', 20));

route('camara', camara); route('mapa', mapa); route('buscar', buscar); route('especie', ficha); route('revisar', revisar);
await getEspecies();                                   // pantalla de inicio: "Cargando especies"
await render();
addEventListener('vuela:usuario', render);          // al entrar o salir se recarga la pantalla
cargarSesion().then(() => sincronizar());             // confirma la sesión y envía lo que haya en la cola
setTimeout(() => document.getElementById('splash').classList.add('out'), 900);

if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(e => console.warn('SW:', e));
