import { badge, hora, esc, fondo } from './components.js';
import { icon } from './icons.js';
export const mapaView = (titulo = 'Tus avistamientos') => `<div class="pad mapa">
<div class="sec"><div><h2>${esc(titulo)}</h2><div class="place">${icon('pin', 15)}La Paz, B.C.S.</div></div>
<span class="count"><i class="dot" style="background:var(--cyan)"></i><span id="count"></span>&nbsp;avistamientos</span></div>
<div class="mgrid">
<div class="map" id="map"><span class="reg">${icon('pin', 18)}La Paz, B.C.S. <small>· Bahía</small></span><button class="loc" aria-label="Centrar ubicación">${icon('locate', 20)}</button><div id="lf"></div><div id="sel"></div></div>
<aside class="mside"><div class="chips fil" id="chips"></div><div class="mlist" id="mlist" aria-label="Lista de avistamientos"></div></aside>
</div></div>`;
const COMO = { 'cámara': 'Identificada con la cámara', ficha: 'Registrada desde la ficha', manual: 'Registrada a mano' };
const ESTADO = { pendiente: 'Pendiente de validar', validado: 'Validado', rechazado: 'Rechazado', 'por sincronizar': 'Por sincronizar' };
export const pin = on => `<span class="mk ${on ? 'on' : ''}">${icon('ave', on ? 22 : 18)}</span>`;
export const seleccion = (a, e) => `<div class="av"><div class="top"><div class="ph"${fondo(e)}></div><div><h4>${esc(e.nombre)}</h4>
<div class="r">${badge(e.estatus)}<span class="sci">${esc(e.cientifico)}</span></div>
<div class="meta">${icon('clock', 13)}${hora(a.fecha)}<s>•</s>${icon('pin', 13)}<b>${esc(a.lugar)}</b></div></div></div>
<div class="act"><span style="color:var(--mut)">${icon('camera', 14)}${esc([COMO[a.origen], ESTADO[a.estado]].filter(Boolean).join(' · '))}</span><a href="#/especie/${esc(e.id)}">Ver ficha ${icon('chevron', 16)}</a></div></div>`;
// Lista lateral (solo en pantallas grandes): un renglón por avistamiento.
export const renglon = (a, e, i, on) => `<button type="button" class="mit${on ? ' on' : ''}" data-i="${i}"><span class="ph"${fondo(e)}></span>
<span><b>${esc(e?.nombre ?? a.especieId)}</b><small>${hora(a.fecha)} · ${esc(a.lugar)}</small></span>${a.estado ? `<em class="est ${esc(a.estado.replace(' ', '-'))}">${esc(ESTADO[a.estado] ?? a.estado)}</em>` : ''}</button>`;
