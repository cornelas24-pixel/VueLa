// VueLa · servidor
// Sirve la PWA y una API JSON que conecta la app con la base de datos vuela_db.
// Toda la lógica de negocio vive en PostgreSQL (sp_registrar_avistamiento,
// sp_revisar_avistamiento, triggers y vistas); aquí solo se traducen los datos
// de la app a parámetros de esos procedimientos.
//
// Inicio de sesión: correo y contraseña verificados en la base (pgcrypto/bcrypt).
// La sesión es una cookie HttpOnly con un token aleatorio; en la tabla sesiones
// solo se guarda su SHA-256. Las rutas que escriben usan el usuario de la sesión.
//
// Arranque:  cd server  →  npm install  →  copiar .env.example como .env  →  npm start
import crypto from 'node:crypto';
import dotenv from 'dotenv';
import express from 'express';
import pg from 'pg';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(AQUI, '.env') });

const RAIZ = path.resolve(AQUI, '..');                        // carpeta del proyecto (index.html)
const PUERTO = Number(process.env.PORT || 3000);
const RADIO_KM = Number(process.env.RADIO_SITIO_KM || 2);
const DIAS_SESION = Number(process.env.DIAS_SESION || 30);
const COOKIE = 'vuela_sesion';

// pg toma PGHOST, PGPORT, PGDATABASE, PGUSER y PGPASSWORD del .env (o de las
// variables de entorno del servicio donde se publique). Pocas conexiones: el
// «Session pooler» del plan gratis de Supabase admite pocas a la vez y las
// comparten todas las copias del servidor (las computadoras del equipo y la publicada).
const pool = new pg.Pool({ max: Number(process.env.PG_POOL_MAX || 5) });
pool.on('error', err => console.error('[db] conexión inactiva con error:', err.message));

const app = express();
// Publicado (Render u otro servicio) la app queda detrás de un proxy con HTTPS:
// así req.ip es la IP real del usuario (límite de intentos) y req.secure indica HTTPS.
if (process.env.TRUST_PROXY || process.env.RENDER) app.set('trust proxy', 1);
app.use(express.json({ limit: '100kb' }));

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------
const ms = d => (d instanceof Date ? d.getTime() : d);
const num = v => (v == null ? null : Number(v));
const origenApp = o => (o === 'camara' ? 'cámara' : o);                  // la app muestra «cámara»
const origenDb = o => String(o ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const milesimas = v => Math.round(Math.min(1, Math.max(0, Number(v))) * 1000);

class ErrorApi extends Error {
  constructor(status, mensaje) { super(mensaje); this.status = status; }
}

// Traduce errores de PostgreSQL a respuestas HTTP. 4xx = el dato no es válido
// (la app no debe reintentarlo); 5xx = problema temporal (la app reintenta).
function responderError(res, err) {
  if (err instanceof ErrorApi) return res.status(err.status).json({ error: err.message });
  const codigo = err.code;
  const mensaje = err.message;
  if (codigo === '23505') return res.status(409).json({ error: mensaje, codigo });
  if (['P0001', '23514', '23503', '23502', '22P02', '22001', '22003', '22007', '22008'].includes(codigo))
    return res.status(422).json({ error: mensaje, codigo });
  if (['ECONNREFUSED', 'ENOTFOUND', '28P01', '3D000', '57P01'].includes(codigo))
    return res.status(503).json({ error: 'La base de datos no está disponible.', codigo });
  console.error('[api] error inesperado:', err);
  return res.status(500).json({ error: 'Error interno del servidor.', codigo });
}

const ruta = fn => async (req, res) => {
  try { await fn(req, res); } catch (err) { responderError(res, err); }
};

function entero(v, nombre) {
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) throw new ErrorApi(400, `${nombre} no es válido.`);
  return n;
}

// ---------------------------------------------------------------------------
// Sesiones
// ---------------------------------------------------------------------------
const sha256 = t => crypto.createHash('sha256').update(t).digest('hex');

function leerCookie(req, nombre) {
  for (const parte of (req.headers.cookie || '').split(';')) {
    const [k, ...v] = parte.trim().split('=');
    if (k === nombre) return decodeURIComponent(v.join('='));
  }
  return null;
}

// Con HTTPS (app publicada) la cookie se marca Secure: nunca viaja sin cifrar.
const ponerCookie = (req, res, valor, segundos) =>
  res.setHeader('Set-Cookie', `${COOKIE}=${valor}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${segundos}${req.secure ? '; Secure' : ''}`);

async function abrirSesion(req, res, usuarioId) {
  const token = crypto.randomBytes(32).toString('hex');
  await pool.query('DELETE FROM sesiones WHERE expira_en < now()');
  await pool.query(`INSERT INTO sesiones (token_hash, usuario_id, expira_en)
                    VALUES ($1, $2, now() + make_interval(days => $3))`, [sha256(token), usuarioId, DIAS_SESION]);
  ponerCookie(req, res, token, DIAS_SESION * 86400);
}

// Usuario de la sesión (o null): token válido, sin vencer y usuario activo.
async function usuarioDeSesion(req) {
  const token = leerCookie(req, COOKIE);
  if (!token || !/^[0-9a-f]{64}$/.test(token)) return null;
  const { rows: [u] } = await pool.query(`
    SELECT u.usuario_id AS id, u.nombre, r.nombre AS rol
    FROM sesiones s
    JOIN usuarios u ON u.usuario_id = s.usuario_id
    JOIN roles    r ON r.rol_id     = u.rol_id
    WHERE s.token_hash = $1 AND s.expira_en > now() AND u.activo`, [sha256(token)]);
  return u ?? null;
}

async function requerirUsuario(req) {
  const u = await usuarioDeSesion(req);
  if (!u) throw new ErrorApi(401, 'Inicia sesión para continuar.');
  return u;
}

async function requerirBiologo(req) {
  const u = await requerirUsuario(req);
  if (u.rol !== 'biologo') throw new ErrorApi(403, 'Solo un biólogo puede revisar avistamientos.');
  return u;
}

// Freno simple contra adivinar contraseñas: 10 intentos fallidos por IP cada 15 minutos.
const intentos = new Map();
function revisarIntentos(ip) {
  const a = intentos.get(ip);
  if (a && Date.now() - a.desde < 15 * 60 * 1000 && a.n >= 10)
    throw new ErrorApi(429, 'Demasiados intentos. Espera unos minutos e intenta de nuevo.');
}
function anotarFallo(ip) {
  const a = intentos.get(ip);
  if (!a || Date.now() - a.desde >= 15 * 60 * 1000) intentos.set(ip, { n: 1, desde: Date.now() });
  else a.n += 1;
}
const texto = (v, max = 200) => (typeof v === 'string' ? v.slice(0, max) : '');

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------
app.use('/api', (req, _res, next) => { console.log(`[api] ${req.method} ${req.originalUrl}`); next(); });

app.get('/api/salud', ruta(async (_req, res) => {
  const { rows: [r] } = await pool.query('SELECT current_database() AS base, now() AS hora');
  res.json({ ok: true, base: r.base, hora: r.hora, radioSitioKm: RADIO_KM });
}));

// Catálogo (mismos campos que data/especies.json; sin clase_yolo ni total_registros)
app.get('/api/especies', ruta(async (_req, res) => {
  const { rows } = await pool.query(`
    SELECT slug AS id, nombre_comun AS nombre, nombre_cientifico AS cientifico, estatus,
           descripcion, habitat, region, foto_url AS foto
    FROM especies
    ORDER BY especie_id`);
  res.json(rows);
}));

// ---- Inicio de sesión ------------------------------------------------------
// Sesión actual (null = invitado)
app.get('/api/sesion', ruta(async (req, res) => {
  res.json({ usuario: await usuarioDeSesion(req) });
}));

// Datos de la cuenta para el panel de perfil: los de la tabla usuarios (sin el hash)
// y un resumen de su actividad. No se guarda nada nuevo: todo se calcula al momento.
app.get('/api/mi-cuenta', ruta(async (req, res) => {
  const { id } = await requerirUsuario(req);
  const { rows: [c] } = await pool.query(`
    SELECT u.nombre, u.correo, r.nombre AS rol, u.creado_en,
           count(a.avistamiento_id)                                AS total,
           count(a.avistamiento_id) FILTER (WHERE a.estado = 'validado')  AS validados,
           count(a.avistamiento_id) FILTER (WHERE a.estado = 'pendiente') AS pendientes,
           count(a.avistamiento_id) FILTER (WHERE a.estado = 'rechazado') AS rechazados,
           count(DISTINCT a.especie_id)                            AS especies,
           (SELECT count(*) FROM revisiones v WHERE v.revisor_id = u.usuario_id) AS revisiones,
           (SELECT count(*) FROM sesiones s
             WHERE s.usuario_id = u.usuario_id AND s.expira_en > now())          AS sesiones,
           (SELECT expira_en FROM sesiones s WHERE s.token_hash = $2)            AS vence
    FROM usuarios u
    JOIN roles r ON r.rol_id = u.rol_id
    LEFT JOIN avistamientos a ON a.usuario_id = u.usuario_id
    WHERE u.usuario_id = $1
    GROUP BY u.usuario_id, r.nombre`, [id, sha256(leerCookie(req, COOKIE))]);
  res.json({
    nombre: c.nombre, correo: c.correo, rol: c.rol, creadoEn: ms(c.creado_en), vence: ms(c.vence),
    sesiones: Number(c.sesiones), revisiones: Number(c.revisiones),
    avistamientos: { total: Number(c.total), validados: Number(c.validados), pendientes: Number(c.pendientes),
      rechazados: Number(c.rechazados), especies: Number(c.especies) },
  });
}));

app.post('/api/login', ruta(async (req, res) => {
  revisarIntentos(req.ip);
  const correo = texto(req.body?.correo), contrasena = texto(req.body?.contrasena);
  if (!correo || !contrasena) throw new ErrorApi(400, 'Escribe tu correo y tu contraseña.');
  const { rows: [u] } = await pool.query(
    'SELECT usuario_id AS id, nombre, rol FROM fn_verificar_credenciales($1, $2)', [correo, contrasena]);
  if (!u) { anotarFallo(req.ip); throw new ErrorApi(401, 'Correo o contraseña incorrectos.'); }
  await abrirSesion(req, res, u.id);
  res.json({ usuario: u });
}));

// Registro: siempre crea un turista (los biólogos los da de alta el administrador por SQL)
app.post('/api/registro', ruta(async (req, res) => {
  revisarIntentos(req.ip);
  const nombre = texto(req.body?.nombre), correo = texto(req.body?.correo), contrasena = texto(req.body?.contrasena);
  let id;
  try {
    ({ rows: [{ id }] } = await pool.query('SELECT fn_registrar_usuario($1, $2, $3) AS id', [nombre, correo, contrasena]));
  } catch (err) {
    if (err.code === '23505') throw new ErrorApi(409, 'Ya existe una cuenta con ese correo.');
    if (err.code === '23514' && /d_correo/.test(err.message)) throw new ErrorApi(422, 'El correo no tiene un formato válido.');
    if (err.code === '22001') throw new ErrorApi(422, 'El nombre o el correo son demasiado largos.');
    throw err;
  }
  await abrirSesion(req, res, id);
  res.status(201).json({ usuario: { id, nombre: nombre.trim(), rol: 'turista' } });
}));

app.post('/api/logout', ruta(async (req, res) => {
  const token = leerCookie(req, COOKIE);
  if (token) await pool.query('DELETE FROM sesiones WHERE token_hash = $1', [sha256(token)]);
  ponerCookie(req, res, '', 0);
  res.json({ ok: true });
}));

// ---- Datos del usuario de la sesión ------------------------------------------
// Historial propio
app.get('/api/mis-avistamientos', ruta(async (req, res) => {
  const { id } = await requerirUsuario(req);
  const { rows } = await pool.query(`
    SELECT a.avistamiento_id, a.uuid_cliente, e.slug, a.latitud, a.longitud, a.fecha_hora,
           a.origen, s.nombre AS sitio, a.estado, a.ubicacion_aprox, d.confianza
    FROM avistamientos a
    JOIN especies e ON e.especie_id = a.especie_id
    JOIN sitios   s ON s.sitio_id   = a.sitio_id
    LEFT JOIN detecciones d ON d.avistamiento_id = a.avistamiento_id
    WHERE a.usuario_id = $1
    ORDER BY a.fecha_hora DESC`, [id]);
  res.json(rows.map(r => ({
    id: r.avistamiento_id, uuid: r.uuid_cliente, especieId: r.slug,
    lat: num(r.latitud), lng: num(r.longitud), fecha: ms(r.fecha_hora),
    origen: origenApp(r.origen), lugar: r.sitio, estado: r.estado,
    ubicacionAprox: r.ubicacion_aprox, confianza: num(r.confianza),
  })));
}));

// Mapa público (invitado): solo validados con ubicación real (vista v_mapa_publico)
app.get('/api/mapa-publico', ruta(async (_req, res) => {
  const { rows } = await pool.query(`
    SELECT avistamiento_id, slug, sitio, latitud, longitud, fecha_hora
    FROM v_mapa_publico ORDER BY fecha_hora DESC`);
  res.json(rows.map(r => ({
    id: r.avistamiento_id, especieId: r.slug, lat: num(r.latitud), lng: num(r.longitud),
    fecha: ms(r.fecha_hora), lugar: r.sitio, estado: 'validado', origen: null,
  })));
}));

// Pendientes que puede revisar el biólogo de la sesión (excluye los suyos)
app.get('/api/pendientes', ruta(async (req, res) => {
  const u = await requerirBiologo(req);
  const { rows } = await pool.query(`
    SELECT a.avistamiento_id, e.slug, s.nombre AS sitio, a.fecha_hora, a.origen, a.latitud, a.longitud,
           a.ubicacion_aprox, au.nombre AS autor, d.confianza, d.modelo_version, ep.slug AS predicha
    FROM avistamientos a
    JOIN especies e  ON e.especie_id = a.especie_id
    JOIN sitios   s  ON s.sitio_id   = a.sitio_id
    JOIN usuarios au ON au.usuario_id = a.usuario_id
    LEFT JOIN detecciones d  ON d.avistamiento_id = a.avistamiento_id
    LEFT JOIN especies    ep ON ep.especie_id = d.especie_predicha_id
    WHERE a.estado = 'pendiente' AND a.usuario_id <> $1      -- RN4: no revisa los suyos
    ORDER BY a.fecha_hora`, [u.id]);
  res.json(rows.map(r => ({
    id: r.avistamiento_id, especieId: r.slug, lugar: r.sitio, fecha: ms(r.fecha_hora),
    lat: num(r.latitud), lng: num(r.longitud), ubicacionAprox: r.ubicacion_aprox,
    origen: origenApp(r.origen), autor: r.autor, confianza: num(r.confianza), modeloVersion: r.modelo_version,
    especiePredicha: r.predicha,
  })));
}));

// Últimas revisiones hechas por el biólogo de la sesión.
app.get('/api/mis-revisiones', ruta(async (req, res) => {
  const u = await requerirBiologo(req);
  const { rows } = await pool.query(`
    SELECT v.avistamiento_id, v.decision, v.comentario, v.revisado_en, e.slug, s.nombre AS sitio, au.nombre AS autor
    FROM revisiones v
    JOIN avistamientos a ON a.avistamiento_id = v.avistamiento_id
    JOIN especies e  ON e.especie_id = a.especie_id
    JOIN sitios   s  ON s.sitio_id   = a.sitio_id
    JOIN usuarios au ON au.usuario_id = a.usuario_id
    WHERE v.revisor_id = $1
    ORDER BY v.revisado_en DESC
    LIMIT 20`, [u.id]);
  res.json(rows.map(r => ({
    id: r.avistamiento_id, especieId: r.slug, lugar: r.sitio, autor: r.autor,
    decision: r.decision, comentario: r.comentario, fecha: ms(r.revisado_en),
  })));
}));

// Asigna el sitio registrado más cercano dentro del radio; si no hay o no hubo GPS: «Otro».
async function asignarSitio(cliente, lat, lng, aprox) {
  if (!aprox) {
    const { rows: [s] } = await cliente.query(`
      SELECT sitio_id, distancia_km FROM (
        SELECT sitio_id,
               6371 * 2 * asin(sqrt(
                   power(sin(radians(latitud - $1::numeric) / 2), 2)
                 + cos(radians($1::numeric)) * cos(radians(latitud))
                 * power(sin(radians(longitud - $2::numeric) / 2), 2))) AS distancia_km
        FROM sitios WHERE nombre <> 'Otro') t
      WHERE distancia_km <= $3
      ORDER BY distancia_km LIMIT 1`, [lat, lng, RADIO_KM]);
    if (s) return s.sitio_id;
  }
  const { rows: [otro] } = await cliente.query(`SELECT sitio_id FROM sitios WHERE nombre = 'Otro'`);
  if (!otro) throw new ErrorApi(500, 'Falta el sitio «Otro» en la tabla sitios.');
  return otro.sitio_id;
}

async function buscarPorUuid(cliente, uuid) {
  const { rows: [a] } = await cliente.query(`
    SELECT a.avistamiento_id, a.estado, s.nombre AS sitio
    FROM avistamientos a JOIN sitios s ON s.sitio_id = a.sitio_id
    WHERE a.uuid_cliente = $1`, [uuid]);
  return a;
}

// Registrar avistamiento (operación compuesta → sp_registrar_avistamiento).
// Es idempotente por uuid: si la app reenvía el mismo avistamiento al
// sincronizar, se responde con el ya guardado y no se duplica.
// El autor es siempre el usuario de la sesión.
app.post('/api/avistamientos', ruta(async (req, res) => {
  const b = req.body ?? {};
  const { id: usuarioId } = await requerirUsuario(req);
  if (b.usuarioId != null && Number(b.usuarioId) !== usuarioId)
    throw new ErrorApi(403, 'Este avistamiento se guardó con otra cuenta; inicia sesión con esa cuenta para enviarlo.');
  const uuid = String(b.uuid ?? '');
  if (!/^[0-9a-f-]{36}$/i.test(uuid)) throw new ErrorApi(400, 'uuid no es válido.');
  const lat = Number(b.lat), lng = Number(b.lng), fecha = Number(b.fecha);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) throw new ErrorApi(400, 'Faltan las coordenadas.');
  if (!Number.isFinite(fecha)) throw new ErrorApi(400, 'Falta la fecha.');
  const origen = origenDb(b.origen || 'camara');
  const aprox = Boolean(b.ubicacionAprox);

  const cliente = await pool.connect();
  try {
    const previo = await buscarPorUuid(cliente, uuid);
    if (previo) return res.status(200).json({ id: previo.avistamiento_id, uuid, estado: previo.estado, lugar: previo.sitio, duplicado: true });

    const { rows: [esp] } = await cliente.query('SELECT especie_id FROM especies WHERE slug = $1', [b.especieId]);
    if (!esp) throw new ErrorApi(422, `La especie «${b.especieId}» no existe en el catálogo.`);

    // Detección: la caja se guarda con 3 decimales y sin salirse del cuadro.
    let det = { especie: null, conf: null, x: null, y: null, w: null, h: null, version: null };
    if (b.deteccion) {
      const d = b.deteccion, c = d.caja ?? {};
      const { rows: [pred] } = await cliente.query('SELECT especie_id FROM especies WHERE slug = $1', [d.especieId]);
      if (!pred) throw new ErrorApi(422, `La especie predicha «${d.especieId}» no existe en el catálogo.`);
      const x = milesimas(c.x), y = milesimas(c.y);
      const w = Math.min(milesimas(c.w), 1000 - x), h = Math.min(milesimas(c.h), 1000 - y);
      det = {
        especie: pred.especie_id, conf: (milesimas(d.confianza) / 1000).toFixed(3),
        x: (x / 1000).toFixed(3), y: (y / 1000).toFixed(3), w: (w / 1000).toFixed(3), h: (h / 1000).toFixed(3),
        version: String(d.modeloVersion || '').slice(0, 20) || null,
      };
    }

    const sitioId = await asignarSitio(cliente, lat, lng, aprox);
    const { rows: [r] } = await cliente.query(`
      CALL sp_registrar_avistamiento(
        p_usuario_id => $1, p_especie_id => $2, p_sitio_id => $3,
        p_latitud => $4, p_longitud => $5,
        p_fecha_hora => to_timestamp($6::double precision / 1000.0),
        p_origen => $7, p_uuid_cliente => $8, p_ubicacion_aprox => $9,
        p_especie_predicha_id => $10, p_confianza => $11,
        p_caja_x => $12, p_caja_y => $13, p_caja_w => $14, p_caja_h => $15,
        p_modelo_version => $16)`,
      [usuarioId, esp.especie_id, sitioId, lat.toFixed(6), lng.toFixed(6), fecha, origen, uuid, aprox,
       det.especie, det.conf, det.x, det.y, det.w, det.h, det.version]);

    const nuevo = await buscarPorUuid(cliente, uuid);
    res.status(201).json({ id: r.p_avistamiento_id, uuid, estado: nuevo.estado, lugar: nuevo.sitio, duplicado: false });
  } catch (err) {
    // Dos envíos simultáneos del mismo uuid: el segundo choca con el UNIQUE → ya existe.
    if (err.code === '23505' && err.constraint === 'uq_avistamientos_uuid_cliente') {
      const previo = await buscarPorUuid(cliente, uuid);
      return res.status(200).json({ id: previo.avistamiento_id, uuid, estado: previo.estado, lugar: previo.sitio, duplicado: true });
    }
    if (err.code === '23505' && err.constraint === 'uq_avistamiento_minuto')
      throw new ErrorApi(409, 'Ya registraste esta especie en este sitio en el mismo minuto.');
    throw err;
  } finally {
    cliente.release();
  }
}));

// Revisión del biólogo de la sesión (→ sp_revisar_avistamiento; reglas RN3 y RN4 en la base)
app.post('/api/revisiones', ruta(async (req, res) => {
  const b = req.body ?? {};
  const { id: revisorId } = await requerirBiologo(req);
  const avistamientoId = entero(b.avistamientoId, 'El avistamiento');
  if (!['validado', 'rechazado'].includes(b.decision)) throw new ErrorApi(400, 'La decisión debe ser validado o rechazado.');
  const comentario = texto(b.comentario, 1000).trim() || null;   // RN3 y RN4 las aplica la base
  if (comentario?.length > 300) throw new ErrorApi(422, 'El comentario no puede pasar de 300 caracteres.');
  await pool.query('CALL sp_revisar_avistamiento($1, $2, $3, $4)', [avistamientoId, revisorId, b.decision, comentario]);
  const { rows: [a] } = await pool.query('SELECT estado FROM avistamientos WHERE avistamiento_id = $1', [avistamientoId]);
  res.status(201).json({ avistamientoId, estado: a.estado });
}));

app.use('/api', (_req, res) => res.status(404).json({ error: 'Ruta de la API no encontrada.' }));

// ---------------------------------------------------------------------------
// Archivos de la app (nunca se sirven server/ ni db/)
// ---------------------------------------------------------------------------
app.use((req, res, next) => {
  if (/^\/(server|db)(\/|$)/i.test(decodeURIComponent(req.path))) return res.status(404).end();
  next();
});
// no-cache: el navegador puede guardar los archivos, pero pregunta al servidor si cambiaron
// (respuesta 304 si no). Así nadie se queda con una versión vieja después de actualizar la app.
app.use(express.static(RAIZ, { dotfiles: 'deny', index: 'index.html', setHeaders: res => res.setHeader('Cache-Control', 'no-cache') }));

// ---------------------------------------------------------------------------
app.listen(PUERTO, async () => {
  console.log(`VueLa en http://localhost:${PUERTO}`);
  try {
    const { rows: [r] } = await pool.query('SELECT current_database() AS base, current_user AS usuario');
    console.log(`Conectado a la base «${r.base}» como «${r.usuario}». Radio para sitios: ${RADIO_KM} km.`);
  } catch (err) {
    console.error(`No se pudo conectar a PostgreSQL (${err.code ?? ''} ${err.message}). Revisa server/.env.`);
    console.error('La app abre igual, pero guardará los avistamientos en el celular hasta que haya base.');
  }
});
