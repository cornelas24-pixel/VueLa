// Revisión de avistamientos (solo biólogos). Todo pasa por la API: la base aplica
// RN3 (una sola revisión), RN4 (solo biólogos activos y nunca los suyos).
import { cargarSesion } from './sesion.js';

async function pedir(url, datos) {
  let r;
  try {
    r = await fetch(url, datos === undefined ? { cache: 'no-store' }
      : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(datos) });
  } catch {
    return { ok: false, error: 'Sin conexión con el servidor. Para revisar necesitas internet.' };
  }
  const j = await r.json().catch(() => ({}));
  if (r.status === 401) cargarSesion();                     // la sesión venció: la app vuelve a invitado
  if (!r.ok) return { ok: false, status: r.status, error: j.error || `Error ${r.status}` };
  return { ok: true, datos: j };
}

export const getPendientes = () => pedir('api/pendientes');
export const getMisRevisiones = () => pedir('api/mis-revisiones');
export const revisar = (avistamientoId, decision, comentario) =>
  pedir('api/revisiones', { avistamientoId, decision, comentario });

// Número de pendientes para el aviso del menú; avisa con el evento 'vuela:pendientes'.
export async function contarPendientes() {
  const r = await getPendientes();
  const n = r.ok ? r.datos.length : null;
  dispatchEvent(new CustomEvent('vuela:pendientes', { detail: n }));
  return n;
}
