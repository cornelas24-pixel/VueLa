# VueLa

PWA para identificar aves de La Paz, B.C.S. con YOLO, conectada a una base de datos PostgreSQL.

```
VueLa-main/
├── index.html, js/, css/, assets/, models/, vendor/   ← la app (PWA)
├── server/                                            ← API Node.js + Express (sirve la app y habla con PostgreSQL)
└── db/                                                ← scripts de la base de datos (ver db/README.md)
```

## Arrancar con base de datos

1. **Base de datos:** crear `vuela_db` y correr `db/01_estructura.sql` → `02_datos.sql` → `03_triggers_procedimientos.sql` (detalles en `db/README.md`).
2. **Node.js 18 o superior:** <https://nodejs.org> (versión LTS).
3. **Servidor** (en una terminal, dentro de la carpeta del proyecto):
   ```bash
   cd server
   npm install
   copy .env.example .env        # en Windows (macOS/Linux: cp .env.example .env)
   ```
   Abrir `server/.env` y poner la contraseña de PostgreSQL en `PGPASSWORD` (la misma que en DBeaver). Luego:
   ```bash
   npm start
   ```
   Debe decir `Conectado a la base «vuela_db»`.
4. Abrir **http://localhost:3000**. La cámara y el GPS solo funcionan en localhost o HTTPS.

## Base de datos en Supabase (compartida por el equipo)

La base del proyecto vive en Supabase (proyecto `vuela`, región East US). Es PostgreSQL 17 normal: se usan los mismos scripts de `db/`.

- **DBeaver:** nueva conexión PostgreSQL con los datos del **Session pooler** (Supabase → botón *Connect* → *Direct* → *Session pooler*): host `aws-1-us-east-1.pooler.supabase.com`, puerto `5432`, base `postgres`, usuario `postgres.qzextuggrzjlliljpbuy` y la contraseña de la base (pídansela a quien creó el proyecto; no se guarda en el repositorio). En la pestaña SSL, activar SSL.
- **Servidor:** en `server/.env` usar esos mismos datos y agregar `PGSSLMODE=no-verify` (ver `server/.env.example`, opción 2).
- **Recargar la base desde cero:** `db/cargar_base_supabase.bat` (corre 01 → 02 → 03 en Supabase leyendo `server/.env`; usa el `psql` del contenedor de Docker).
- No usar el *Transaction pooler*: rompe `SET ROLE`, las tablas temporales y las sesiones A/B.
- El plan gratis **pausa el proyecto tras una semana sin uso** (reactivarlo en el panel antes de la demostración) y **no hace respaldos automáticos**: sacar `pg_dump` (prueba P08).
- La *Data API* de Supabase está desactivada: las tablas no son accesibles por la API pública; solo por conexión directa a PostgreSQL.

## Publicada en internet (Render)

Para usarla desde cualquier celular (la cámara y el GPS piden HTTPS), el servidor se publica en [Render](https://render.com) conectado a este repositorio y a la base de Supabase.

- **Servicio:** *Web Service*, rama `main`, *Root Directory* vacío.
  - *Build Command:* `npm ci --prefix server`
  - *Start Command:* `node server/server.js`
  - *Health Check Path:* `/api/salud`
- **Variables de entorno** (las mismas de `server/.env` con Supabase): `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGSSLMODE=no-verify`, y opcionales `RADIO_SITIO_KM`, `DIAS_SESION`, `PG_POOL_MAX`. El archivo `.env` **no** se sube a GitHub.
- Cada `git push` a `main` vuelve a publicar la app. Recuerden subir `VERSION` en `sw.js` para que los celulares descarguen la versión nueva.
- En el plan gratis el servicio se duerme tras un rato sin visitas: la primera carga después puede tardar cerca de un minuto.
- En el celular: abrir la dirección en Chrome → menú → **Instalar app** (o *Agregar a pantalla de inicio*).

### App Android (.apk)

- Descarga: <https://vuela-app.onrender.com/descargas/VueLa.apk> (en el celular hay que permitir «instalar apps desconocidas» para el navegador).
- Se generó con [PWABuilder](https://www.pwabuilder.com) (*Trusted Web Activity*): el .apk abre la app publicada a pantalla completa, así que **los cambios que se publiquen en Render se ven solos**, sin generar otro .apk.
- `.well-known/assetlinks.json` vincula el .apk con la página (sin él, la app se abre con una barra de navegador). El servidor lo sirve en `/.well-known/assetlinks.json`.
- La llave de firma (`android/signing.keystore` y `android/signing-key-info.txt`) **no se sube a GitHub**; guárdenla: hace falta para firmar una versión nueva del .apk con la misma firma (ver `android/LEEME.txt`).

## Cómo funciona

- **Inicio de sesión:** el botón de perfil (arriba a la derecha) abre **Iniciar sesión / Crear cuenta**; con sesión abierta muestra **Mi cuenta** (correo, rol, miembro desde, vencimiento de la sesión, dispositivos con sesión y el resumen de sus avistamientos) y **Cerrar sesión**.
  - Las cuentas nuevas son de **turista**. Los **biólogos** los da de alta el administrador por SQL (ver `db/README.md`).
  - Usuarios de prueba: `turista1@vuela.test`, `biologo1@vuela.test`, etc., con la contraseña `vuela2026`.
  - La contraseña se guarda cifrada (bcrypt) en la base; la sesión es una cookie `HttpOnly` y dura 30 días (`DIAS_SESION` en `server/.env`).
  - Sin sesión se navega como **invitado**: solo catálogo y **mapa público** (avistamientos validados con ubicación real); no puede usar la cámara.
  - Los avistamientos guardados sin conexión se envían cuando esa misma cuenta tiene la sesión abierta.
- **Registro:** al capturar se envía la especie, coordenadas, fecha y la **detección completa** (confianza, caja y versión del modelo). La base lo guarda con `sp_registrar_avistamiento`, así que se aplican todas las reglas (RN1, RN6, RN7…). Si una regla lo rechaza, la app muestra el motivo.
- **Revisión (biólogos):** la pantalla **Revisar** (botón con el número de pendientes en el encabezado; en computadora, en la barra lateral; también desde *Mi cuenta*) lista los avistamientos pendientes de otros usuarios con la especie, autor, fecha, lugar (enlace al mapa) y la confianza del modelo. El biólogo los **valida** o **rechaza** con un comentario opcional. La base aplica RN3 (una sola revisión) y RN4 (solo biólogos activos, nunca los suyos). Los validados pasan al mapa público.
  - La app no guarda la foto que tomó el usuario: la imagen de la tarjeta es la **foto de referencia** de la especie.
- **Sitio:** el servidor asigna el sitio registrado más cercano dentro de `RADIO_SITIO_KM` (2 km por defecto, en `server/.env`). Sin sitio cercano o sin GPS se asigna «Otro».
- **Sin conexión:** cada avistamiento lleva un `uuid` generado en el celular. Si no hay red, queda en una cola local y se envía al volver la conexión. Reenviar nunca duplica (la API es idempotente por `uuid_cliente`). En el panel de perfil se ve cuántos faltan por sincronizar y cuáles se rechazaron.
- **Catálogo:** viene de la tabla `especies`; sin conexión se usa la última copia o `data/especies.json`.

## Diseño responsivo

`css/responsive.css` adapta la app a tres tamaños:

- **Celular (menos de 600 px):** el diseño original.
- **Tablet (600 a 1023 px):** usa todo el ancho; catálogo en varias columnas; la cuenta sale como menú bajo el botón de perfil.
- **Computadora (1024 px o más):** barra lateral en lugar de la barra de abajo; mapa a toda la altura con la lista de avistamientos a un lado; ficha con la foto junto al texto.

## Modelo YOLO

Ver `models/README.md` (`models/vuela.onnx` + `models/labels.json`).

- `?mock` en la URL fuerza el detector falso (por ejemplo `http://localhost:3000/?mock`). Sus detecciones se guardan con `modelo_version = 'mock'` para excluirlas en las consultas de calidad.
- La versión del modelo real se define en `MODELO_VERSION` (`js/services/detector/onnxDetector.js`). Hoy es **`'vuela-v1'`, provisional**: cambiarla cuando se defina la versión del modelo entrenado.

## API (server/server.js)

| Método | Ruta | Qué hace |
|---|---|---|
| GET | `/api/salud` | Comprueba la conexión con la base. |
| GET | `/api/especies` | Catálogo. |
| GET | `/api/sesion` | Usuario de la sesión actual (`null` = invitado). |
| POST | `/api/login` | Inicia sesión con correo y contraseña (10 intentos fallidos por IP cada 15 min). |
| POST | `/api/registro` | Crea una cuenta de turista e inicia sesión. |
| POST | `/api/logout` | Cierra la sesión (la borra de la tabla `sesiones`). |
| GET | `/api/mi-cuenta` | Panel de perfil: nombre, correo, rol, fecha de alta, vencimiento de la sesión, dispositivos con sesión y conteo de avistamientos (y revisiones si es biólogo). |
| GET | `/api/mis-avistamientos` | Historial del usuario de la sesión. |
| GET | `/api/mapa-publico` | Vista `v_mapa_publico`. |
| POST | `/api/avistamientos` | Registra un avistamiento (→ `sp_registrar_avistamiento`). |
| GET | `/api/pendientes` | Pendientes que puede revisar el biólogo de la sesión (no incluye los suyos), con autor, lugar, coordenadas y confianza del modelo. |
| POST | `/api/revisiones` | El biólogo de la sesión valida o rechaza, con comentario opcional (→ `sp_revisar_avistamiento`). |
| GET | `/api/mis-revisiones` | Últimas 20 revisiones del biólogo de la sesión. |

Las reglas de negocio viven en la base de datos; el servidor solo traduce los datos. Respuestas 4xx = el dato no cumple una regla (no se reintenta); 5xx o sin red = se reintenta después.

> Registrar y revisar requieren sesión: el autor y el revisor siempre son el usuario de la sesión, no un dato que mande la app. Para publicarlo en internet faltaría servirlo con HTTPS (la cookie se marcaría `Secure`).

## Sin base de datos

`python -m http.server 8000` → http://localhost:8000 sigue funcionando: el catálogo sale de `data/especies.json` y los avistamientos se quedan en la cola del navegador hasta que haya servidor.

Al publicar cambios, sube `VERSION` en `sw.js` para renovar la caché. `vendor/` contiene Leaflet y onnxruntime-web (para funcionar sin internet).
