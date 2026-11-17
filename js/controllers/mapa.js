import { mapaView, pin, seleccion, renglon } from '../views/mapa.js';
import { chips, filtrosEstatus, SINGULAR } from '../views/components.js';
import { getEspecies } from '../services/api.js';
import { getAvistamientos, getMapaPublico } from '../services/storage.js';
import { getUsuario } from '../services/sesion.js';
import { CENTRO } from '../models/models.js';
import { ubicar } from '../services/geo.js';

export default async function (root, _id, vivo) {
  // Con usuario: su historial. Invitado: mapa público (solo validados, vista v_mapa_publico).
  const invitado = !getUsuario();
  const [especies, todos] = await Promise.all([getEspecies(), invitado ? getMapaPublico() : getAvistamientos()]);
  if (!vivo()) return;
  root.innerHTML = mapaView(invitado ? 'Mapa público' : 'Tus avistamientos');
  const $ = s => root.querySelector(s), opciones = ['Todos', ...filtrosEstatus(especies)];
  const espDe = a => especies.find(e => e.id === a.especieId);
  let filtro = 'Todos', sel = 0, yo;

  const mapa = L.map($('#lf'), { zoomControl: false, attributionControl: true }).setView([CENTRO.lat, CENTRO.lng], 13);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 18, attribution: '© OpenStreetMap' }).addTo(mapa);
  const capa = L.layerGroup().addTo(mapa);

  const pintar = () => {
    const lista = todos.filter(a => filtro === 'Todos' || espDe(a)?.estatus === SINGULAR[filtro]);
    sel = Math.max(0, Math.min(sel, lista.length - 1));
    $('#count').textContent = lista.length;
    capa.clearLayers();
    lista.forEach((a, i) => {
      const on = i === sel, s = on ? 40 : 32;
      L.marker([a.lat, a.lng], { icon: L.divIcon({ className: '', html: pin(on), iconSize: [s, s], iconAnchor: [s / 2, s / 2] }), zIndexOffset: on ? 1000 : 0 })
        .on('click', () => { sel = i; pintar(); }).addTo(capa);
    });
    $('#sel').innerHTML = lista.length && espDe(lista[sel]) ? seleccion(lista[sel], espDe(lista[sel])) : '<p class="empty">Sin avistamientos con este filtro.</p>';
    $('#chips').innerHTML = chips(opciones, filtro, 'mapa', todos.length);
    $('#mlist').innerHTML = lista.map((a, i) => renglon(a, espDe(a), i, i === sel)).join('');
    $('#mlist .on')?.scrollIntoView({ block: 'nearest' });
    return lista;
  };
  root.onclick = ev => {
    const it = ev.target.closest('.mit');
    if (it) { sel = Number(it.dataset.i); const a = pintar()[sel]; if (a) mapa.panTo([a.lat, a.lng]); return; }
    const c = ev.target.closest('.chip');
    if (c) { filtro = c.dataset.f; sel = 0; const l = pintar(); if (l.length) mapa.fitBounds(L.latLngBounds(l.map(a => [a.lat, a.lng])), { padding: [40, 40], maxZoom: 15 }); }
    if (ev.target.closest('.loc')) ubicar().then(p => {
      if (!p || !vivo()) return;
      yo?.remove(); yo = L.circleMarker([p.lat, p.lng], { radius: 8, color: '#fff', weight: 3, fillColor: '#0d94da', fillOpacity: 1 }).addTo(mapa);
      mapa.setView([p.lat, p.lng], 15);
    });
  };
  const l = pintar();
  if (l.length) mapa.fitBounds(L.latLngBounds(l.map(a => [a.lat, a.lng])), { padding: [40, 40], maxZoom: 15 });
  setTimeout(() => mapa.invalidateSize(), 0);
  // Al girar el celular o cambiar el tamaño de la ventana, Leaflet debe recalcular el mapa.
  const ro = new ResizeObserver(() => mapa.invalidateSize());
  ro.observe($('#map'));
  return () => { ro.disconnect(); mapa.remove(); };
}
