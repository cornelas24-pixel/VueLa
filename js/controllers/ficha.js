import { fichaView } from '../views/ficha.js';
import { getEspecie } from '../services/api.js';
import { getAvistamientos, addAvistamiento } from '../services/storage.js';

const MENSAJE = { guardado: 'Guardado en tu almacén', 'en cola': 'Guardado; se enviará al tener conexión' };

export default async function (root, id, vivo) {
  const e = await getEspecie(id);
  if (!e) { root.innerHTML = '<p class="pad">No se encontró la especie. <a href="#/buscar">Volver a buscar</a></p>'; return; }
  const a = (await getAvistamientos()).find(x => x.especieId === id);
  if (!vivo()) return;
  root.innerHTML = fichaView(e, a);
  root.querySelector('#save').onclick = async ev => {
    const btn = ev.currentTarget;
    if (btn.disabled) return;
    btn.disabled = true;
    const r = await addAvistamiento({ especieId: id, origen: 'ficha' });
    btn.disabled = false;
    btn.lastChild.textContent = MENSAJE[r.estado] ?? `No se guardó: ${r.error}`;
  };
}
