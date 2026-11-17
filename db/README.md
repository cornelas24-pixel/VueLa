# VueLa · Base de datos (PostgreSQL)

Base de Datos II · UABCS. Scripts construidos a partir del **Documento de diseño v2** (`VueLa_Diseno_Base_de_Datos_v2.pdf`), `data/especies.json`, `models/labels.json` y el código de la PWA.

- PostgreSQL **13 o superior** (usa `gen_random_uuid()`). Probado en **PostgreSQL 16.15**.
- Base de pruebas: `vuela_db` · base de restauración: `vuela_restore`.
- Todos los scripts se probaron completos desde una base vacía, incluidas las sesiones A/B en paralelo y el respaldo/restauración.

## Contenido

| Archivo | Qué hace | Pruebas |
|---|---|---|
| `01_estructura.sql` | 2 dominios, 10 tablas (7 de negocio + bitácora + `ts_avistamiento` + `sesiones`), PK, 10 FK (8 de negocio + `ts_avistamiento` + `sesiones`), CHECK de tabla y de dominio, UNIQUE e índices únicos, `pgcrypto` y `fn_hash_contrasena`. Borra y recrea todo. | — |
| `02_datos.sql` | 61 registros de prueba y recálculo de contadores. | P01, P02, P03 |
| `03_triggers_procedimientos.sql` | 5 triggers (`trg_auditoria` en 5 tablas), `sp_registrar_avistamiento`, `sp_revisar_avistamiento`, vistas públicas y rol `vuela_invitado`. | P04, P13, éxito/rechazo de cada objeto |
| `04_transacciones.sql` | COMMIT, ROLLBACK, SAVEPOINT, bitácora, falla SQL, respaldo, copia sombra y WAL. | P05, P06, P07, P08, P14 |
| `05_sesion_A.sql` / `06_sesion_B.sql` | 53 pasos alternados para concurrencia. | P09, P10, P11, P12 |
| `07_validaciones.sql` | Consultas de calidad (Reto 1.4), operaciones clave y verificación de restauración. Solo lee. | P08 (comparación) |
| `respaldo/`, `capturas/`, `reporte/` | Carpetas para los entregables. | — |

## Orden de ejecución

```
crear vuela_db y vuela_restore (vacía)
01 → 02 → 03 → 07 → 04 → 05/06 (pasos alternados) → 07
```

### Con psql

```bash
createdb -U postgres vuela_db
createdb -U postgres vuela_restore
psql -U postgres -d vuela_db -f 01_estructura.sql
psql -U postgres -d vuela_db -f 02_datos.sql
psql -U postgres -d vuela_db -f 03_triggers_procedimientos.sql
psql -U postgres -d vuela_db -f 07_validaciones.sql
psql -U postgres -d vuela_db -f 04_transacciones.sql
```

### Con DBeaver

1. Conexión a `vuela_db` en modo **auto-commit** (las transacciones se abren con `BEGIN` explícito).
2. Abrir cada script y ejecutarlo como script (**Alt+X**). En 04 aparecen errores marcados `ERROR ESPERADO`: elegir **Ignorar** y continuar.
3. Para 05 y 06: abrir cada archivo en su propio editor (cada uno con su propia conexión; en DBeaver es la opción por defecto «Open separate connection for each editor»). Ejecutar los pasos en orden numérico, alternando (PASO 01 en A, PASO 02 en B…). Seleccionar el bloque del paso y ejecutar con Alt+X. Los pasos marcados **(espera)** se quedan bloqueados: seguir con el siguiente paso en la otra sesión.
4. Al terminar, correr `07_validaciones.sql`: todo debe salir en `OK` (las dos filas `INFO` son informativas).

### Para repetir

- 01 borra y recrea todo, así que **para volver a correr 02 o 03 hay que empezar desde 01** (03 contiene pruebas que modifican los datos; 02 se niega a correr si los triggers ya existen).
- 05/06 suponen la base tal como queda después de 01 → 02 → 03 → 07 → 04.

## Cómo leer las pruebas

Las pruebas de rechazo usan la función auxiliar `fn_probar_rechazo(prueba, sql, código_esperado)`: ejecuta la sentencia, deshace cualquier efecto y devuelve una fila con el SQLSTATE. Así los scripts 02 y 03 corren completos sin detenerse y cada caso queda en una tabla lista para captura:

```
 prueba                              | resultado     | codigo | mensaje
 P02a confianza 1.4                  | OK: rechazada | 23514  | value for domain d_probabilidad violates ...
```

Si alguna fila dice `FALLA`, algo no se comportó como se esperaba.

## Resultados verificados

| Prueba | Resultado obtenido |
|---|---|
| P01 | 4 casos rechazados con 23505 (avistamiento en el mismo minuto, correo con otras mayúsculas, nombre de especie, uuid_cliente). |
| P02 | 7 casos rechazados con 23514 (confianza 1.4, caja fuera del cuadro, estado «dudoso», fecha futura, origen «cámara», latitud, correo). |
| P03 | 4 casos rechazados con 23503 (especie 999, especie predicha inexistente, rol inexistente, borrar un revisado). |
| P04 | Turista revisa, autor revisa, ya revisado, UPDATE directo del estado, regresar a pendiente, insertar ya validado: todos rechazados por trigger. |
| P05 | COMMIT: avistamiento + detección, contador +1 y evento en bitácora con `usuario_app_id`. |
| P06 | Detección inválida en el 2.º paso → 23514, luego 25P02; ROLLBACK sin huérfano ni cambio en el contador. |
| P07 | SAVEPOINT: el duplicado se deshace y se conservan los 3 válidos; sin savepoint se pierde todo. |
| P08 | `pg_dump -Fc` → `pg_restore` en `vuela_restore`: conteos por tabla y huella de contadores idénticos. |
| P09 | READ COMMITTED: el contador y el COUNT cambian dentro de la misma transacción; REPEATABLE READ: no cambian. READ UNCOMMITTED no ve datos sin confirmar. |
| P10 | La revisión de B espera (`wait_event = transactionid`, `bloqueado_por = {pid de A}`) hasta el COMMIT de A. |
| RN3 | Dos biólogos revisan el mismo pendiente: B espera y recibe «RN3: ya fue revisado»; queda una sola revisión. |
| P11 | Bloqueo cruzado → `40P01 deadlock detected`; bloqueando en orden de id no hay deadlock. |
| P12 | Marca 11:00 después de una 11:05 aceptada → rechazada (40001). SERIALIZABLE con RN6 → `40001 could not serialize access`; en READ COMMITTED el turista queda con 6 pendientes. |
| P13 | `vuela_invitado` lee las dos vistas; leer `usuarios` o `sesiones`, insertar, llamar al procedimiento o verificar contraseñas → 42501. |
| Login | Contraseña en texto plano o de menos de 8 caracteres → 23514 (P02h, P02i). Login correcto sin importar mayúsculas del correo; contraseña incorrecta, usuario inactivo o correo inexistente → 0 filas. Registro: correo repetido → 23505; contraseña corta, correo inválido o sin nombre → 23514. La bitácora registra el alta sin el hash. |
| P14 | El cambio de estatus por SQL deja **un** evento de especies con `usuario_db` del administrador; el contador no genera eventos. |
| Calidad | Las 11 verificaciones con esperado 0 salen en 0 después de cada etapa. |

## Inicio de sesión

Agregado después del documento de diseño v2 (que lo dejaba fuera de alcance). Todo vive en la base:

- **`usuarios.contrasena_hash`:** hash **bcrypt** calculado dentro de PostgreSQL con `pgcrypto` (`fn_hash_contrasena`, mínimo 8 caracteres). Un CHECK (`ck_usuarios_contrasena_bcrypt`) impide guardar una contraseña en texto plano.
- **`sesiones`:** una fila por sesión abierta en la app, con el **SHA-256 del token** (nunca el token), el usuario y la fecha de vencimiento (30 días). El token viaja en una cookie `HttpOnly` que la app no puede leer.
- **`fn_verificar_credenciales(correo, contraseña)`:** devuelve el usuario si el correo existe, está activo y la contraseña coincide; si no, ninguna fila.
- **`fn_registrar_usuario(nombre, correo, contraseña)`:** crea la cuenta, **siempre como turista**.
- **Bitácora:** `trg_auditoria` nunca copia `contrasena_hash`.
- **Invitado:** quien no inicia sesión. `vuela_invitado` no puede leer `usuarios` ni `sesiones`.

**Contraseña de prueba** de los 7 usuarios de `02_datos.sql`: `vuela2026` (por ejemplo, `turista1@vuela.test` / `vuela2026`; `turista5` está inactivo y no puede entrar).

**Tareas del administrador (por SQL, en DBeaver):**

```sql
-- Dar de alta un biólogo
INSERT INTO usuarios (nombre, correo, rol_id, contrasena_hash)
VALUES ('Nombre Apellido', 'correo@ejemplo.com',
        (SELECT rol_id FROM roles WHERE nombre = 'biologo'),
        fn_hash_contrasena('contraseña-inicial'));

-- Convertir un turista en biólogo
UPDATE usuarios SET rol_id = (SELECT rol_id FROM roles WHERE nombre = 'biologo')
WHERE lower(correo) = 'correo@ejemplo.com';

-- Restablecer una contraseña olvidada y cerrar sus sesiones abiertas
UPDATE usuarios SET contrasena_hash = fn_hash_contrasena('nueva-contraseña')
WHERE lower(correo) = 'correo@ejemplo.com';
DELETE FROM sesiones
WHERE usuario_id = (SELECT usuario_id FROM usuarios WHERE lower(correo) = 'correo@ejemplo.com');

-- Desactivar una cuenta (ya no puede entrar; sus avistamientos se conservan)
UPDATE usuarios SET activo = false WHERE lower(correo) = 'correo@ejemplo.com';
```

**Bases que ya existían** (Supabase o Docker): `migracion_login.sql` agrega todo lo anterior sin borrar datos y pone `vuela2026` a los usuarios que no tengan contraseña. Con Supabase: `migrar_login_supabase.bat`. Las bases nuevas no lo necesitan: 01, 02 y 03 ya lo traen.

## Decisiones del equipo aplicadas

Las «decisiones pendientes» de la sección 12 del documento que se resolvieron para esta versión:

- **RN6 incluida** (máximo 5 pendientes por turista, validada en `sp_registrar_avistamiento`).
- **RN8 incluida** (vistas públicas y rol `vuela_invitado`).
- El mapa público **no** muestra avistamientos con ubicación aproximada (como propone la v2).

Siguen pendientes y **no** se resolvieron en los scripts: el radio para asignar el sitio más cercano (la app tendrá que mandarlo o elegirlo), versión exacta de PostgreSQL común del equipo, fechas de entrega e integrantes.

## Ajustes respecto al documento de diseño v2

Son refuerzos que no cambian el modelo. Conviene anotarlos en una v3 del documento:

1. **`trg_proteger_estado` también en INSERT**: un avistamiento nuevo solo entra como `pendiente`. Sin esto, un INSERT con `estado = 'validado'` saltaba RN4.
2. **`trg_contar_avistamiento` también en `UPDATE OF especie_id`**: si se corrige la especie, se mueven los dos contadores y RN5 se sigue cumpliendo.
3. **`sp_registrar_avistamiento`**: exige la detección completa cuando el origen es `camara` y la rechaza para `ficha`/`manual`. Devuelve el id creado (parámetro `INOUT p_avistamiento_id`). No hace COMMIT, para poder usarlo dentro de transacciones con SAVEPOINT.
4. **Reto 9 (marcas de tiempo)**: la regla «se rechaza toda operación con marca anterior a la última aceptada» se implementó en los pasos 41 y 42 de las sesiones con `INSERT … ON CONFLICT … WHERE ultima_marca < nueva` sobre `ts_avistamiento`. La operación de ejemplo es corregir la ubicación de un avistamiento, porque el documento no define cuál es.
5. **Resincronización de secuencias al final de 02**: los INSERT rechazados de P01–P03 consumen valores de IDENTITY (es normal en PostgreSQL); se resincronizan para que los id de las pruebas de 03 sean predecibles.
6. Restricciones con **nombre explícito** (`ck_…`, `fk_…`, `uq_…`) para que los mensajes de error sean claros en el reporte.
7. `SET timezone = 'America/Mazatlan'` al inicio de los scripts para ver las fechas en hora de La Paz (solo afecta cómo se muestran).

## Datos que hay que confirmar o reemplazar

| Dato | Estado actual | Qué falta |
|---|---|---|
| Coordenadas de los sitios | Tomadas de fuentes públicas (abajo). «Otro» usa el `CENTRO` de La Paz de `js/models/models.js`. | Validarlas con el biólogo del proyecto. |
| `modelo_version` | `'mock'` para el detector falso; **`'vuela-v1'` es provisional** para el modelo real. | Que quien entrena YOLO defina la versión. |
| Usuarios de prueba | Genéricos (`biologo1@vuela.test`, `turista1@vuela.test`…). | Nada, salvo que el profesor pida otros. |
| `descripcion` / `habitat` | Textos preliminares redactados a partir de Audubon y Wikipedia (fuentes abajo). | Que los valide el biólogo del proyecto. |
| `foto_url` | `assets/aves/<slug>.jpg`: fotos de `aves_comunes.pdf` (en Calandria y Pinzón, la del macho). | Confirmar que se pueden usar: algunas traen marca de agua del fotógrafo; conviene dar crédito o reemplazarlas. |
| Nombres alternos | `aves_comunes.pdf` menciona «paloma pitahayera», «Cuitlacoche» y «Quelele». Se guardan los nombres de `especies.json`, como indica el documento. | Si se quieren buscar por nombre alterno, haría falta una columna nueva. |

### Fuentes de los textos del catálogo

Textos redactados con datos de estas fuentes (tamaño, plumaje, hábitat y distribución):

- Audubon Guide to North American Birds: [Hooded Oriole](https://www.audubon.org/field-guide/bird/hooded-oriole), [Northern Cardinal](https://www.audubon.org/field-guide/bird/northern-cardinal), [Gila Woodpecker](https://www.audubon.org/field-guide/bird/gila-woodpecker), [Cactus Wren](https://www.audubon.org/field-guide/bird/cactus-wren), [Crested Caracara](https://www.audubon.org/field-guide/bird/crested-caracara), [Turkey Vulture](https://www.audubon.org/field-guide/bird/turkey-vulture), [White-winged Dove](https://www.audubon.org/field-guide/bird/white-winged-dove), [Common Ground Dove](https://www.audubon.org/field-guide/bird/common-ground-dove)
- Wikipedia en español: [Icterus cucullatus](https://es.wikipedia.org/wiki/Icterus_cucullatus), [Cardinalis cardinalis](https://es.wikipedia.org/wiki/Cardinalis_cardinalis), [Haemorhous mexicanus](https://es.wikipedia.org/wiki/Haemorhous_mexicanus), [Campylorhynchus brunneicapillus](https://es.wikipedia.org/wiki/Campylorhynchus_brunneicapillus), [Toxostoma cinereum](https://es.wikipedia.org/wiki/Toxostoma_cinereum)
- Wikipedia en inglés: [Cactus wren](https://en.wikipedia.org/wiki/Cactus_wren) (descripción y subespecies de Baja California)

Para cargar fotos y textos en una base que ya existe sin borrar nada: `actualizar_catalogo.sql` (o `actualizar_catalogo_docker.bat` con Docker). Las bases nuevas ya los traen desde `02_datos.sql`.

### Fuentes de las coordenadas

- Malecón — 24.166499, -110.312176 · [Sygic Travel](https://travel.sygic.com/en/poi/malecon-poi:25029)
- Estero El Mogote — 24.163, -110.362 · [Wikipedia: El Mogote](https://en.wikipedia.org/wiki/El_Mogote)
- Cerro de la Calavera — 24.18696, -110.29907 · [AroundUs](https://es.aroundus.com/p/171422516-cerro-de-la-calavera)
- Playa Balandra — 24.321733, -110.324203 · [LatLong.net](https://www.latlong.net/place/balandra-beach-la-paz-mexico-27541.html)
- Playa El Tesoro — 24.254563, -110.314923 · [Beach Atlas](https://www.beachatlas.com/es/el-tesoro)

## Notas de permisos (extra RN8)

- `vuela_invitado` es un rol del **servidor**: 03 lo crea solo si no existe. El respaldo guarda los GRANT pero no crea el rol; en otro servidor hay que crearlo antes de restaurar.
- Para probar con `SET ROLE vuela_invitado`, quien corre el script debe ser superusuario o miembro del rol. 03 se otorga la membresía automáticamente si el usuario creó el rol. Si el rol **ya existía y lo creó otro usuario**, un superusuario debe ejecutar `GRANT vuela_invitado TO <usuario>;`.

## Correspondencia con la app

| App (localStorage) | Base de datos |
|---|---|
| `especieId` (slug) | `avistamientos.especie_id` (buscar por `especies.slug`) |
| `lat`, `lng` | `latitud`, `longitud` |
| `fecha` (milisegundos) | `fecha_hora = to_timestamp(fecha / 1000.0)` |
| `origen: 'cámara'` | `'camara'` (sin acento; con acento se rechaza, P02e) |
| sin GPS (punto aleatorio cerca del centro) | `ubicacion_aprox = true`, sitio «Otro» |
| detector (`especieId`, `confianza`, `caja`) | `detecciones` (`especie_predicha_id`, `confianza`, `caja_x/y/w/h`, `modelo_version`) |
| — | `uuid_cliente`: la app debe generarlo por avistamiento para sincronizar sin duplicar |
