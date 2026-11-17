import { esc, hora } from './components.js';
import { icon } from './icons.js';

const ROL = { biologo: 'Biólogo', turista: 'Turista' };

// Inicial del usuario en el botón de perfil (invitado: icono de persona).
export const avatar = u => (u ? `<span class="ini">${esc(u.nombre.trim()[0] ?? '?')}</span>` : icon('person', 18));

const sync = (enCola, rechazados) => `
  ${enCola ? `<div class="usync">${icon('clock', 15)}${enCola} avistamiento(s) por sincronizar</div>` : ''}
  ${rechazados.length ? `<div class="urech"><b>No se pudieron guardar (${rechazados.length})</b>
    ${rechazados.map(r => `<p>${esc(r.especieId)} · ${hora(r.fecha)}<br><small>${esc(r.error)}</small></p>`).join('')}
    <button id="udescartar" type="button">Descartar avisos</button></div>` : ''}`;

const fecha = ms => new Date(ms).toLocaleDateString('es-MX', { day: 'numeric', month: 'short', year: 'numeric' });
const dato = (ic, txt, val) => `<div class="udato">${icon(ic, 16)}<span>${txt}</span><b>${val}</b></div>`;

// Resumen de la cuenta: números de avistamientos y datos de la cuenta.
const resumen = (u, c) => {
  if (c === undefined) return '<div class="ucargando" aria-busy="true">Cargando tus datos…</div>';
  if (!c) return '';
  const a = c.avistamientos;
  return `
  <div class="ustats" aria-label="Tus avistamientos">
    <div><b>${a.total}</b><small>Avistamientos</small></div>
    <div class="ok"><b>${a.validados}</b><small>Validados</small></div>
    <div class="pe"><b>${a.pendientes}</b><small>Pendientes</small></div>
    <div class="no"><b>${a.rechazados}</b><small>Rechazados</small></div>
  </div>
  <div class="udatos">
    ${dato('ave', 'Especies distintas', a.especies)}
    ${u.rol === 'biologo' ? dato('verified', 'Revisiones hechas', c.revisiones) : ''}
    ${dato('calendar', 'Miembro desde', fecha(c.creadoEn))}
    ${c.vence ? dato('lock', 'Tu sesión vence', fecha(c.vence)) : ''}
    ${dato('devices', 'Dispositivos con sesión', c.sesiones)}
  </div>
  ${c.sinConexion ? '<p class="muted">Sin conexión: datos de la última vez que hubo internet.</p>' : ''}`;
};

// Con sesión: datos de la cuenta, resumen, sincronización y cerrar sesión.
const cuentaView = (u, enCola, rechazados, error, c, porRevisar) => `
<div class="ucard" role="dialog" aria-label="Mi cuenta">
  <div class="uhead"><b>Mi cuenta</b><button id="ucerrar" type="button" aria-label="Cerrar">${icon('back', 20)}</button></div>
  <div class="uyo">${avatar(u)}<span><b>${esc(u.nombre)}</b>${c?.correo ? `<small class="ucorreo">${esc(c.correo)}</small>` : ''}</span><em class="urol">${esc(ROL[u.rol] ?? u.rol)}</em></div>
  ${resumen(u, c)}
  ${u.rol === 'biologo' ? `<a id="urevisar" class="ubtn" href="#/revisar">${icon('verified', 18)}Revisar avistamientos${porRevisar ? ` <span class="ucuenta">${porRevisar}</span>` : ''}</a>` : ''}
  ${enCola || rechazados.length ? sync(enCola, rechazados) : `<div class="usync">${icon('clock', 15)}Todo sincronizado</div>`}
  ${error ? `<p class="uerr" role="alert">${esc(error)}</p>` : ''}
  <button id="usalir" class="ubtn sec" type="button">Cerrar sesión</button>
</div>`;

// Sin sesión: iniciar sesión o crear cuenta.
const accesoView = ({ modo, error, ocupado, valores, enCola, rechazados }) => {
  const crear = modo === 'crear';
  return `
<div class="ucard" role="dialog" aria-label="${crear ? 'Crear cuenta' : 'Iniciar sesión'}">
  <div class="uhead"><b>${crear ? 'Crear cuenta' : 'Iniciar sesión'}</b><button id="ucerrar" type="button" aria-label="Cerrar">${icon('back', 20)}</button></div>
  <div class="utabs" role="tablist">
    <button type="button" role="tab" data-modo="entrar" aria-selected="${!crear}" class="${crear ? '' : 'on'}">Iniciar sesión</button>
    <button type="button" role="tab" data-modo="crear" aria-selected="${crear}" class="${crear ? 'on' : ''}">Crear cuenta</button>
  </div>
  <form id="uform" class="uform">
    ${crear ? `<label>Nombre<input name="nombre" autocomplete="name" required minlength="2" maxlength="80" value="${esc(valores.nombre ?? '')}"></label>` : ''}
    <label>Correo<input name="correo" type="email" autocomplete="email" required maxlength="120" value="${esc(valores.correo ?? '')}"></label>
    <label>Contraseña<input name="contrasena" type="password" autocomplete="${crear ? 'new-password' : 'current-password'}" required minlength="8" maxlength="200"></label>
    ${crear ? '<small class="muted">Mínimo 8 caracteres.</small>' : ''}
    ${error ? `<p class="uerr" role="alert">${esc(error)}</p>` : ''}
    <button class="ubtn" type="submit"${ocupado ? ' disabled' : ''}>${ocupado ? 'Un momento…' : crear ? 'Crear cuenta' : 'Entrar'}</button>
  </form>
  <p class="muted">Sin cuenta navegas como <b>invitado</b>: puedes ver el catálogo y el mapa público, pero no registrar avistamientos.</p>
  ${crear ? '<p class="muted">Las cuentas nuevas son de turista. Las de biólogo las da de alta el administrador del proyecto.</p>' : ''}
  ${sync(enCola, rechazados)}
</div>`;
};

export const panelView = s => (s.usuario ? cuentaView(s.usuario, s.enCola, s.rechazados, s.error, s.cuenta, s.porRevisar) : accesoView(s));
