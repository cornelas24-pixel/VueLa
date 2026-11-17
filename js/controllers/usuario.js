// Panel del botón de perfil: iniciar sesión, crear cuenta, ver la cuenta,
// la cola de sincronización y cerrar sesión.
import { panelView, avatar } from '../views/usuario.js';
import { getUsuario, iniciarSesion, crearCuenta, cerrarSesion, getCuenta } from '../services/sesion.js';
import { pendientesDeEnviar, getRechazados, descartarRechazados, sincronizar } from '../services/storage.js';
import { contarPendientes } from '../services/revision.js';

const boton = document.getElementById('avatar');
export const pintarAvatar = () => {
  const u = getUsuario();
  boton.innerHTML = avatar(u);
  boton.title = u ? `${u.nombre} (mi cuenta)` : 'Iniciar sesión';
  boton.setAttribute('aria-label', boton.title);
  // Lo que solo ven los biólogos (Revisar) se muestra con [data-rol=biologo] en el CSS.
  document.getElementById('app').dataset.rol = u?.rol ?? '';
  if (u?.rol === 'biologo') contarPendientes();
};

// Aviso con el número de pendientes en el menú (barra lateral, encabezado y panel).
let porRevisar = null;
addEventListener('vuela:pendientes', ev => {
  porRevisar = ev.detail;
  document.querySelectorAll('.nbadge').forEach(b => { b.hidden = !porRevisar; b.textContent = porRevisar > 99 ? '99+' : porRevisar ?? ''; });
  pintar();
});

let panel;
const estado = { modo: 'entrar', error: '', ocupado: false, valores: {}, cuenta: undefined };
const cerrar = () => { panel?.remove(); panel = null; };

// Pide al servidor los datos de la cuenta (undefined = cargando).
async function cargarCuenta() {
  const c = await getCuenta();
  if (!panel) return;
  estado.cuenta = c; pintar();
}

function pintar() {
  if (!panel) return;
  const u = getUsuario();
  panel.innerHTML = panelView({
    ...estado, usuario: u, porRevisar,
    enCola: pendientesDeEnviar(u?.id), rechazados: getRechazados(),
  });
}

async function enviarFormulario(form) {
  const d = Object.fromEntries(new FormData(form));
  estado.valores = { nombre: d.nombre, correo: d.correo };
  estado.ocupado = true; estado.error = ''; pintar();
  const r = estado.modo === 'crear'
    ? await crearCuenta(d.nombre, d.correo, d.contrasena)
    : await iniciarSesion(d.correo, d.contrasena);
  estado.ocupado = false;
  if (!r.ok) { estado.error = r.error; pintar(); panel?.querySelector('[name=contrasena]')?.focus(); return; }
  Object.assign(estado, { modo: 'entrar', error: '', valores: {} });
  cerrar();
  sincronizar();                                    // envía lo que esta cuenta tenía en la cola
}

function abrir() {
  if (panel) return cerrar();
  Object.assign(estado, { error: '', ocupado: false });
  panel = document.createElement('div');
  panel.className = 'upanel';
  document.getElementById('app').append(panel);
  panel.onclick = async ev => {
    if (ev.target === panel || ev.target.closest('#ucerrar') || ev.target.closest('#urevisar')) return cerrar();
    if (ev.target.closest('#udescartar')) { descartarRechazados(); return pintar(); }
    if (ev.target.closest('#usalir')) {
      const r = await cerrarSesion();
      if (r.ok) return cerrar();
      estado.error = r.error; return pintar();
    }
    const tab = ev.target.closest('[data-modo]');
    if (tab) { Object.assign(estado, { modo: tab.dataset.modo, error: '' }); pintar(); }
  };
  panel.onsubmit = ev => { ev.preventDefault(); if (!estado.ocupado) enviarFormulario(ev.target); };
  pintar();
  setTimeout(() => panel?.setAttribute('data-listo', ''), 300);   // después de la animación de entrada
  panel.querySelector('input')?.focus();
  if (getUsuario()) { estado.cuenta = undefined; pintar(); sincronizar().then(cargarCuenta); }
}

boton.onclick = abrir;
addEventListener('vuela:usuario', pintarAvatar);
addEventListener('vuela:sync', pintar);
pintarAvatar();
