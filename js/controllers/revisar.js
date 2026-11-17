// Pantalla de revisión (#/revisar): el biólogo de la sesión valida o rechaza
// los avistamientos pendientes de otros usuarios (→ sp_revisar_avistamiento).
import { revisarView, sinPermisoView } from '../views/revisar.js';
import { getEspecies } from '../services/api.js';
import { getUsuario } from '../services/sesion.js';
import { getPendientes, getMisRevisiones, revisar } from '../services/revision.js';

export default async function (root, _id, vivo) {
  const u = getUsuario();
  if (u?.rol !== 'biologo') { root.innerHTML = sinPermisoView(!u); return; }

  const especies = await getEspecies();
  const especie = id => especies.find(e => e.id === id);
  const st = { pendientes: null, revisiones: null, error: '', aviso: '' };
  const estados = {};                                  // por avistamiento: { comentario, error, ocupado }
  let temporizador;

  const pintar = () => {
    if (!vivo()) return;
    // Conservar lo que el biólogo ya escribió en los comentarios al volver a pintar.
    root.querySelectorAll('.rcard').forEach(c => { (estados[c.dataset.id] ??= {}).comentario = c.querySelector('.rcom').value; });
    root.innerHTML = revisarView(st, especie, estados);
  };

  const cargar = async () => {
    st.error = '';
    const [p, v] = await Promise.all([getPendientes(), getMisRevisiones()]);
    if (!vivo()) return;
    if (p.ok) st.pendientes = p.datos; else { st.pendientes = st.pendientes ?? null; st.error = p.error; }
    if (v.ok) st.revisiones = v.datos;
    dispatchEvent(new CustomEvent('vuela:pendientes', { detail: p.ok ? p.datos.length : null }));
    pintar();
  };

  root.onclick = async ev => {
    if (ev.target.closest('#rrecargar')) { st.aviso = ''; return cargar(); }
    const btn = ev.target.closest('[data-d]');
    if (!btn) return;
    const card = btn.closest('.rcard'), id = Number(card.dataset.id), decision = btn.dataset.d;
    const e = (estados[id] ??= {});
    e.comentario = card.querySelector('.rcom').value;
    if (e.ocupado) return;
    Object.assign(e, { ocupado: true, error: '' }); pintar();
    const r = await revisar(id, decision, e.comentario);
    e.ocupado = false;
    if (!r.ok) {
      e.error = r.error;
      // 409/422: ya lo revisó otro biólogo o una regla lo impide → se recarga la lista.
      if (r.status === 409 || /^RN3/.test(r.error)) { st.aviso = ''; await cargar(); st.error = r.error; pintar(); return; }
      return pintar();
    }
    delete estados[id];
    const a = st.pendientes.find(x => x.id === id);
    st.pendientes = st.pendientes.filter(x => x.id !== id);
    if (a) st.revisiones = [{ id, especieId: a.especieId, lugar: a.lugar, autor: a.autor, decision, comentario: e.comentario.trim() || null, fecha: Date.now() },
      ...(st.revisiones ?? [])].slice(0, 20);
    st.aviso = `${especie(a?.especieId)?.nombre ?? 'Avistamiento'} de ${a?.autor ?? ''}: ${decision === 'validado' ? 'validado' : 'rechazado'}.`;
    dispatchEvent(new CustomEvent('vuela:pendientes', { detail: st.pendientes.length }));
    pintar();
    clearTimeout(temporizador);
    temporizador = setTimeout(() => { st.aviso = ''; root.querySelector('.raviso.ok')?.remove(); }, 4000);
  };

  pintar();
  await cargar();
  return () => clearTimeout(temporizador);
}
