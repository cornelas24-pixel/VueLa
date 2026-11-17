// Catálogo de especies. Viene de la API (tabla especies en PostgreSQL); sin conexión
// se usa la última copia guardada y, si no hay, data/especies.json.
import { Especie } from '../models/models.js';
const K = 'vuela.catalogo';
let cache;

const sinNulos = o => Object.fromEntries(Object.entries(o).filter(([, v]) => v != null));

async function cargar() {
  try {
    const r = await fetch('api/especies', { cache: 'no-store' });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const lista = await r.json();
    try { localStorage.setItem(K, JSON.stringify(lista)); } catch { /* sin almacenamiento */ }
    return lista;
  } catch {
    try { const guardada = JSON.parse(localStorage.getItem(K)); if (guardada?.length) return guardada; } catch { /* nada */ }
    return (await fetch('data/especies.json')).json();
  }
}

export async function getEspecies() {
  cache ??= (await cargar()).map(o => new Especie(sinNulos(o)));
  return cache;
}
export const getEspecie = async id => (await getEspecies()).find(e => e.id === id);
