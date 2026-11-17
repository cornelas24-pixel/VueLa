import { badge, hora, esc, fondo } from './components.js';
import { icon } from './icons.js';

const COMO = { 'cámara': 'Identificada con la cámara', ficha: 'Registrada desde la ficha', manual: 'Registrada a mano' };
const pct = v => `${Math.round(v * 100)}%`;
const mapaOSM = a => `https://www.openstreetmap.org/?mlat=${a.lat}&mlon=${a.lng}#map=16/${a.lat}/${a.lng}`;

// Confianza del modelo YOLO (de la tabla detecciones). Los registros desde la ficha no tienen detección.
const confianza = a => {
  if (a.confianza == null) return '<p class="rnota">Sin detección del modelo: la especie la eligió el usuario.</p>';
  const nivel = a.confianza >= 0.8 ? 'alta' : a.confianza >= 0.5 ? 'media' : 'baja';
  return `<div class="rconf ${nivel}"><span>Confianza del modelo</span><b>${pct(a.confianza)}</b><i><i style="width:${pct(a.confianza)}"></i></i>
    <small>${a.modeloVersion === 'mock' ? 'Detector de prueba (mock): no es una detección real' : `Modelo ${esc(a.modeloVersion)}`}</small></div>`;
};

export const tarjetaPendiente = (a, e, sugerida, estado = {}) => `
<article class="rcard" data-id="${a.id}">
  <div class="ph"${fondo(e)}><small>Foto de referencia</small></div>
  <div class="rbody">
    <div><b class="rnom">${esc(e?.nombre ?? a.especieId)}</b> ${e ? badge(e.estatus) : ''}<span class="sci">${esc(e?.cientifico ?? '')}</span></div>
    <ul class="rmeta">
      <li>${icon('person', 14)}Registrado por <b>${esc(a.autor)}</b></li>
      <li>${icon('clock', 14)}${hora(a.fecha)}</li>
      <li>${icon('pin', 14)}${esc(a.lugar)}${a.ubicacionAprox ? ' · <em>ubicación aproximada</em>' : ''}
        ${a.lat != null ? `<a href="${mapaOSM(a)}" target="_blank" rel="noopener">Ver en mapa</a>` : ''}</li>
      <li>${icon('camera', 14)}${esc(COMO[a.origen] ?? a.origen)}</li>
    </ul>
  </div>
  ${confianza(a)}
  ${sugerida ? `<p class="raviso">${icon('flash', 14)}El modelo sugirió <b>${esc(sugerida.nombre)}</b>, pero se registró como ${esc(e?.nombre ?? a.especieId)}.</p>` : ''}
  <input class="rcom" name="comentario" maxlength="300" placeholder="Comentario (opcional; recomendado al rechazar)" value="${esc(estado.comentario ?? '')}" aria-label="Comentario de la revisión">
  ${estado.error ? `<p class="uerr" role="alert">${esc(estado.error)}</p>` : ''}
  <div class="racts">
    <button type="button" class="rno" data-d="rechazado"${estado.ocupado ? ' disabled' : ''}>Rechazar</button>
    <button type="button" class="rsi" data-d="validado"${estado.ocupado ? ' disabled' : ''}>${icon('check', 18, 2.5)}Validar</button>
  </div>
</article>`;

const renglon = (v, e) => `<li><span class="ph"${fondo(e)}></span><span><b>${esc(e?.nombre ?? v.especieId)}</b>
  <small>${esc(v.autor)} · ${esc(v.lugar)} · ${hora(v.fecha)}</small>${v.comentario ? `<small class="rcoment">«${esc(v.comentario)}»</small>` : ''}</span>
  <em class="est ${v.decision}">${v.decision === 'validado' ? 'Validado' : 'Rechazado'}</em></li>`;

export const revisarView = ({ pendientes, revisiones, error, aviso }, especie, estados) => `<div class="pad revisar">
<div class="ttl"><h2>Revisar avistamientos</h2><button class="tune" id="rrecargar" aria-label="Actualizar">${icon('refresh', 20)}</button></div>
<p class="muted rsub">Valida o rechaza los avistamientos de otros usuarios. Los validados aparecen en el mapa público. Cada avistamiento se revisa una sola vez y no puedes revisar los tuyos.</p>
${aviso ? `<p class="raviso ok" role="status">${icon('check', 15, 2.5)}${esc(aviso)}</p>` : ''}
${error ? `<p class="uerr" role="alert">${esc(error)}</p>` : ''}
${pendientes == null ? (error ? '' : '<div class="ucargando">Cargando pendientes…</div>') : `
<div class="sum"><span><b>${pendientes.length}</b> pendiente(s) por revisar</span></div>
${pendientes.length ? `<div class="rlist">${pendientes.map(a => tarjetaPendiente(a, especie(a.especieId),
    a.especiePredicha && a.especiePredicha !== a.especieId ? especie(a.especiePredicha) : null, estados[a.id])).join('')}</div>`
  : `<div class="empty">${icon('verified', 28)}<p>No hay avistamientos pendientes. ¡Todo revisado!</p></div>`}`}
${revisiones?.length ? `<h3 class="rh3">Tus últimas revisiones</h3><ul class="rhist">${revisiones.map(v => renglon(v, especie(v.especieId))).join('')}</ul>` : ''}
</div>`;

export const sinPermisoView = invitado => `<div class="pad"><div class="empty">${icon('lock', 28)}
<p>${invitado ? 'Inicia sesión con una cuenta de biólogo para revisar avistamientos.' : 'Solo las cuentas de biólogo pueden revisar avistamientos.'}</p></div></div>`;
