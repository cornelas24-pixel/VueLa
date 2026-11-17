// Sesión de la app. El servidor guarda la sesión en una cookie HttpOnly (la app
// nunca ve el token); aquí solo se recuerda quién es el usuario, para mostrarlo
// y para seguir funcionando sin conexión. null = invitado (solo consulta).
const K = 'vuela.usuario', KC = 'vuela.cuenta';
const leer = (k, def) => { try { return JSON.parse(localStorage.getItem(k)) ?? def; } catch { return def; } };
const escribir = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* sin almacenamiento */ } };

export const getUsuario = () => leer(K, null);

function guardar(u) {
  const nuevo = u ? { id: u.id, nombre: u.nombre, rol: u.rol } : null;
  const cambio = JSON.stringify(getUsuario()) !== JSON.stringify(nuevo);
  escribir(K, nuevo);
  if (cambio) try { localStorage.removeItem(KC); } catch { /* sin almacenamiento */ }
  if (cambio) dispatchEvent(new CustomEvent('vuela:usuario', { detail: nuevo }));
}

async function enviar(url, datos) {
  let r;
  try {
    r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(datos ?? {}) });
  } catch {
    return { ok: false, error: 'Sin conexión con el servidor. Intenta de nuevo cuando tengas internet.' };
  }
  const j = await r.json().catch(() => ({}));
  if (!r.ok) return { ok: false, error: j.error || (r.status >= 500 ? 'El servidor no está disponible.' : `Error ${r.status}`) };
  return { ok: true, ...j };
}

// Pregunta al servidor quién tiene la sesión. Sin conexión (o si el servidor no
// tiene API) se conserva el último usuario conocido.
export async function cargarSesion() {
  try {
    const r = await fetch('api/sesion', { cache: 'no-store' });
    if (!r.ok) return getUsuario();
    const { usuario } = await r.json();
    guardar(usuario);
    return usuario;
  } catch {
    return getUsuario();
  }
}

export async function iniciarSesion(correo, contrasena) {
  const r = await enviar('api/login', { correo, contrasena });
  if (r.ok) guardar(r.usuario);
  return r;
}

export async function crearCuenta(nombre, correo, contrasena) {
  const r = await enviar('api/registro', { nombre, correo, contrasena });
  if (r.ok) guardar(r.usuario);
  return r;
}

// Sin conexión no se puede cerrar la sesión en el servidor: se avisa en lugar de
// fingir que se cerró (al volver la red, la sesión seguiría abierta).
export async function cerrarSesion() {
  const r = await enviar('api/logout');
  if (r.ok) guardar(null);
  return r;
}

// Datos de la cuenta para el panel de perfil (correo, fecha de alta y resumen de
// avistamientos). Sin conexión se muestra la última copia, marcada como vieja.
export async function getCuenta() {
  const u = getUsuario();
  if (!u) return null;
  const copia = leer(KC, null);
  const vieja = copia?.id === u.id ? { ...copia, sinConexion: true } : null;
  try {
    const r = await fetch('api/mi-cuenta', { cache: 'no-store' });
    if (r.status === 401) { await cargarSesion(); return null; }
    if (!r.ok) return vieja;
    const c = { id: u.id, ...(await r.json()) };
    escribir(KC, c);
    return c;
  } catch {
    return vieja;
  }
}
