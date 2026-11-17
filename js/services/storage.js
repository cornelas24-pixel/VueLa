// Avistamientos. Se guardan en PostgreSQL a través de la API (sp_registrar_avistamiento).
// Cada avistamiento lleva un uuid generado aquí (uuid_cliente): primero entra a una cola
// local y se envía; si no hay conexión se queda en la cola y se reenvía después.
// La API es idempotente por uuid, así que reenviar nunca duplica.
// Cada avistamiento en cola es de la cuenta que lo capturó: solo se envía cuando
// esa cuenta tiene la sesión abierta (el servidor usa el usuario de la sesión).
import { Avistamiento, CENTRO } from '../models/models.js';
import { getUsuario, cargarSesion } from './sesion.js';

const COLA = 'vuela.cola', RECH = 'vuela.rechazados', HIST = 'vuela.historial.';
const leer = (k, def) => { try { return JSON.parse(localStorage.getItem(k)) ?? def; } catch { return def; } };
const escribir = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* sin almacenamiento */ } };

// crypto.randomUUID solo existe en contextos seguros (HTTPS o localhost).
const nuevoUuid = () => crypto.randomUUID?.() ??
  '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, c =>
    (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16));

async function getJson(url, respaldo) {
  try {
    const r = await fetch(url, { cache: 'no-store' });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const datos = await r.json();
    escribir(respaldo, datos);
    return datos;
  } catch {
    return leer(respaldo, []);
  }
}

// Historial del usuario de la sesión (de la base) + lo que aún está en la cola local.
// Si la sesión venció (401), se avisa a sesion.js y se muestra la última copia.
export async function getAvistamientos() {
  const u = getUsuario();
  if (!u) return [];
  let hist;
  try {
    const r = await fetch('api/mis-avistamientos', { cache: 'no-store' });
    if (r.status === 401) { cargarSesion(); throw new Error('sin sesión'); }
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    hist = await r.json();
    escribir(HIST + u.id, hist);
  } catch {
    hist = leer(HIST + u.id, []);
  }
  const enCola = leer(COLA, [])
    .filter(a => a.usuarioId === u.id && !hist.some(h => h.uuid === a.uuid))
    .map(a => ({ ...a, lugar: a.lugar ?? 'Por sincronizar', estado: 'por sincronizar' }));
  return [...enCola, ...hist].map(o => new Avistamiento(o));
}

// Mapa público (invitado): solo avistamientos validados con ubicación real.
export async function getMapaPublico() {
  return (await getJson('api/mapa-publico', HIST + 'publico')).map(o => new Avistamiento(o));
}

export const pendientesDeEnviar = usuarioId => leer(COLA, []).filter(a => a.usuarioId === usuarioId).length;
export const getRechazados = () => leer(RECH, []);
export const descartarRechazados = () => escribir(RECH, []);

function quitarDeCola(uuid) { escribir(COLA, leer(COLA, []).filter(a => a.uuid !== uuid)); }

// Envía en orden la cola de la cuenta con sesión. Respuestas: 2xx guardado ·
// 401 sesión vencida: se queda en cola · otro 4xx rechazado por una regla (no se
// reintenta; queda en «rechazados» con el motivo) · 5xx o sin red: se queda en cola.
let enCurso = null;
export function sincronizar() {
  enCurso ??= (async () => {
    const resultado = {};
    const u = getUsuario();
    for (const item of leer(COLA, []).filter(a => a.usuarioId === u?.id)) {
      let r;
      try {
        r = await fetch('api/avistamientos', {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(item),
        });
      } catch { break; }                                   // sin red
      if (r.status === 401) { cargarSesion(); break; }     // sesión vencida: volver a iniciar sesión
      if (r.ok) {
        quitarDeCola(item.uuid);
        resultado[item.uuid] = { ...(await r.json().catch(() => ({}))), estado: 'guardado' };
      } else if (r.status >= 400 && r.status < 500 && r.status !== 404 && r.status !== 405) {
        const e = await r.json().catch(() => ({}));
        quitarDeCola(item.uuid);
        escribir(RECH, [...leer(RECH, []), { ...item, error: e.error || `Error ${r.status}` }]);
        resultado[item.uuid] = { estado: 'rechazado', error: e.error || `Error ${r.status}` };
      } else break;                                        // servidor o base no disponibles
    }
    dispatchEvent(new CustomEvent('vuela:sync'));
    return resultado;
  })().finally(() => { enCurso = null; });
  return enCurso;
}

// Registra un avistamiento. Devuelve { estado: 'guardado' | 'en cola' | 'rechazado', error? }.
// a = { especieId, origen, lat?, lng?, lugar?, deteccion? }
export async function addAvistamiento(a) {
  const u = getUsuario();
  if (!u) return { estado: 'rechazado', error: 'Inicia sesión (botón de perfil) para registrar avistamientos.' };
  // Sin GPS se coloca cerca del centro de La Paz y se marca como ubicación aproximada.
  const sinGps = a.lat == null || a.lng == null;
  const j = () => (Math.random() - .5) * .02;
  const item = {
    uuid: nuevoUuid(), usuarioId: u.id, especieId: a.especieId, origen: a.origen ?? 'cámara', fecha: Date.now(),
    lat: sinGps ? CENTRO.lat + j() : a.lat, lng: sinGps ? CENTRO.lng + j() : a.lng,
    ubicacionAprox: sinGps, lugar: a.lugar, deteccion: a.deteccion ?? null,
  };
  escribir(COLA, [...leer(COLA, []), item]);
  await enCurso?.catch(() => {});                         // si ya había un envío, esperar a que termine
  const r = await sincronizar();
  return r[item.uuid] ?? { estado: 'en cola' };
}

addEventListener('online', () => sincronizar());
