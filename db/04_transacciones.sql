-- =====================================================================
-- VueLa · Base de Datos II · UABCS
-- 04_transacciones.sql — COMMIT, ROLLBACK, SAVEPOINT, bitácora, respaldo,
-- copia sombra y WAL (Retos 4, 5 y 6; pruebas P05, P06, P07, P08 y P14).
-- Basado en: Documento de diseño v2, secciones 5, 9 y 10.
--
-- Orden: 01 → 02 → 03 → 07 → 04.
-- Los errores marcados «ERROR ESPERADO» son parte de la demostración.
--   · psql: correr completo con  psql -d vuela_db -f 04_transacciones.sql
--   · DBeaver: ejecutar por bloques (Ctrl+Enter) o como script (Alt+X) y
--     elegir «Ignorar» cuando aparezca un ERROR ESPERADO.
-- Usuarios: 3 Turista 1 · 4 Turista 2 · 6 Turista 4 · 2 Biólogo 2
-- =====================================================================

SET timezone = 'America/Mazatlan';

-- =====================================================================
-- RETO 4 · COMMIT y ROLLBACK
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1 P05 · Operación compuesta válida → COMMIT conserva todo
-- ---------------------------------------------------------------------
SELECT total_registros AS cardenal_antes FROM especies WHERE slug = 'cardenal-rojo';

BEGIN;                                   -- estado: ACTIVA
CALL sp_registrar_avistamiento(
    p_usuario_id => 3, p_especie_id => 2, p_sitio_id => 1,
    p_latitud => 24.166700, p_longitud => -110.311800,
    p_fecha_hora => '2026-11-11 07:20:00-07', p_origen => 'camara',
    p_uuid_cliente => 'b0000000-0000-4000-8000-000000000001',
    p_especie_predicha_id => 2, p_confianza => 0.903,
    p_caja_x => 0.25, p_caja_y => 0.20, p_caja_w => 0.40, p_caja_h => 0.50,
    p_modelo_version => 'vuela-v1');
-- AISLAMIENTO: si en este momento otra sesión consulta este uuid, no lo ve
-- (el dato aún no está confirmado). Probarlo en DBeaver con otro editor.
SELECT txid_current() AS transaccion_en_curso;
COMMIT;                                  -- estado: CONFIRMADA

-- Todo quedó: avistamiento, detección, contador +1 y evento en la bitácora.
SELECT a.avistamiento_id, a.estado, d.deteccion_id, d.confianza
FROM avistamientos a JOIN detecciones d USING (avistamiento_id)
WHERE a.uuid_cliente = 'b0000000-0000-4000-8000-000000000001';
SELECT total_registros AS cardenal_despues FROM especies WHERE slug = 'cardenal-rojo';
SELECT b.tabla, b.operacion, b.registro_id, b.usuario_db, b.usuario_app_id
FROM bitacora_auditoria b JOIN avistamientos a ON a.avistamiento_id = b.registro_id
WHERE b.tabla = 'avistamientos' AND a.uuid_cliente = 'b0000000-0000-4000-8000-000000000001';

-- DURABILIDAD: desconectar y volver a conectar (DBeaver: Desconectar/Conectar;
-- psql: \c vuela_db) y repetir la consulta de arriba: el avistamiento sigue ahí.

-- ---------------------------------------------------------------------
-- 4.2 P06 · Falla en el segundo paso → ROLLBACK, sin huérfanos
--     Los dos pasos se escriben a mano para ver la falla entre ellos.
-- ---------------------------------------------------------------------
SELECT total_registros AS cardenal_antes FROM especies WHERE slug = 'cardenal-rojo';

BEGIN;                                   -- estado: ACTIVA
-- Paso 1: el avistamiento entra (y el trigger ya sumó 1 al contador)
INSERT INTO avistamientos (uuid_cliente, usuario_id, especie_id, sitio_id, fecha_hora, latitud, longitud)
VALUES ('b0000000-0000-4000-8000-000000000002', 3, 2, 1, '2026-11-11 07:35:00-07', 24.166600, -110.311700);
SELECT total_registros AS cardenal_dentro_de_la_transaccion FROM especies WHERE slug = 'cardenal-rojo';
-- Paso 2: detección con confianza 1.4  → ERROR ESPERADO 23514
INSERT INTO detecciones (avistamiento_id, especie_predicha_id, confianza, caja_x, caja_y, caja_w, caja_h, modelo_version)
SELECT avistamiento_id, 2, 1.4, 0.25, 0.20, 0.40, 0.50, 'vuela-v1'
FROM avistamientos WHERE uuid_cliente = 'b0000000-0000-4000-8000-000000000002';
-- estado: FALLIDA. Cualquier sentencia ahora → ERROR ESPERADO 25P02
-- (current transaction is aborted, commands ignored until end of transaction block)
SELECT 1 AS no_se_ejecuta;
ROLLBACK;                                -- se deshace también el paso 1

-- Ni avistamiento huérfano ni cambio en el contador.
SELECT count(*) AS huerfanos FROM avistamientos
WHERE uuid_cliente = 'b0000000-0000-4000-8000-000000000002';
SELECT total_registros AS cardenal_despues FROM especies WHERE slug = 'cardenal-rojo';


-- =====================================================================
-- RETO 5 · SAVEPOINT (P07): salida de campo con tres avistamientos
-- Turista 2 en el Cerro de la Calavera.
-- =====================================================================
BEGIN;
-- A: primer avistamiento
CALL sp_registrar_avistamiento(4, 3, 3, 24.186800, -110.299300, '2026-11-11 08:05:10-07', 'camara',
    'b0000000-0000-4000-8000-000000000003', false, 3, 0.871, 0.30, 0.25, 0.30, 0.45, 'vuela-v1');
SAVEPOINT antes_de_b;
-- B: se captura por error el mismo pájaro en el mismo minuto → ERROR ESPERADO 23505 (RN1)
CALL sp_registrar_avistamiento(4, 3, 3, 24.186800, -110.299300, '2026-11-11 08:05:40-07', 'camara',
    NULL, false, 3, 0.866, 0.31, 0.25, 0.30, 0.45, 'vuela-v1');
ROLLBACK TO SAVEPOINT antes_de_b;        -- se recupera solo lo posterior al savepoint; A sigue
-- B corregido: era otra especie
CALL sp_registrar_avistamiento(4, 7, 3, 24.187100, -110.299000, '2026-11-11 08:12:00-07', 'camara',
    'b0000000-0000-4000-8000-000000000004', false, 7, 0.948, 0.10, 0.05, 0.70, 0.60, 'vuela-v1');
-- C: tercer avistamiento (anotado a mano)
CALL sp_registrar_avistamiento(4, 6, 3, 24.187300, -110.298700, '2026-11-11 08:20:00-07', 'manual',
    'b0000000-0000-4000-8000-000000000005');
COMMIT;

-- Se conservan los tres válidos.
SELECT a.avistamiento_id, a.fecha_hora, e.nombre_comun, a.origen, a.estado
FROM avistamientos a JOIN especies e USING (especie_id)
WHERE a.uuid_cliente IN ('b0000000-0000-4000-8000-000000000003',
                         'b0000000-0000-4000-8000-000000000004',
                         'b0000000-0000-4000-8000-000000000005')
ORDER BY a.fecha_hora;

-- Diferencia con un ROLLBACK total: Turista 4 en Playa El Tesoro.
BEGIN;
CALL sp_registrar_avistamiento(6, 8, 5, 24.254700, -110.315000, '2026-11-11 09:00:10-07', 'camara',
    'b0000000-0000-4000-8000-000000000006', false, 8, 0.902, 0.20, 0.30, 0.35, 0.40, 'vuela-v1');
-- Duplicado sin savepoint → ERROR ESPERADO 23505
CALL sp_registrar_avistamiento(6, 8, 5, 24.254700, -110.315000, '2026-11-11 09:00:50-07', 'camara',
    NULL, false, 8, 0.899, 0.20, 0.30, 0.35, 0.40, 'vuela-v1');
ROLLBACK;                                -- se pierde también el primero

SELECT count(*) AS conservados_sin_savepoint FROM avistamientos
WHERE uuid_cliente = 'b0000000-0000-4000-8000-000000000006';


-- =====================================================================
-- RETO 6 · Bitácora y recuperación
-- =====================================================================

-- Marca para ver solo los eventos de esta sección.
DROP TABLE IF EXISTS marca_bitacora;
CREATE TEMP TABLE marca_bitacora AS
SELECT COALESCE(max(bitacora_id), 0) AS ultimo FROM bitacora_auditoria;

-- ---------------------------------------------------------------------
-- 6.1 Cinco eventos reales generados por los triggers
-- ---------------------------------------------------------------------
-- Evento 1 · P14: el administrador cambia por SQL el estatus de una especie.
-- (Demostración: se regresa a su valor original al final de 6.1.)
UPDATE especies SET estatus = 'Migratoria' WHERE slug = 'paloma-alas-blancas';

-- Evento 2 · P14: después se registra un avistamiento de esa especie.
-- El contador sube, pero NO genera un evento de especies.
CALL sp_registrar_avistamiento(6, 8, 5, 24.254800, -110.315100, '2026-11-11 09:30:00-07', 'camara',
    'b0000000-0000-4000-8000-000000000007', false, 8, 0.915, 0.22, 0.28, 0.36, 0.42, 'vuela-v1');

-- Eventos 3 y 4: Biólogo 2 rechaza el #15 (detectado con el detector falso).
-- Genera el INSERT en revisiones y el UPDATE del estado en avistamientos.
CALL sp_revisar_avistamiento(15, 2, 'rechazado',
    'Detección del detector falso (mock); la foto no permite confirmar la especie.');

-- Evento 5: el administrador corrige por SQL la descripción de un sitio.
UPDATE sitios SET descripcion = 'Malecón de La Paz, frente a la bahía. Coordenadas aproximadas por validar.'
WHERE nombre = 'Malecón';

-- Eventos de esta sección: usuario_db = usuario de PostgreSQL; usuario_app_id
-- NULL cuando el cambio fue por SQL directo (administrador).
SELECT b.bitacora_id, b.tabla, b.operacion, b.registro_id, b.usuario_db, b.usuario_app_id,
       b.fecha_hora,
       b.datos_anteriores ->> 'estatus' AS estatus_antes,
       b.datos_nuevos     ->> 'estatus' AS estatus_despues,
       b.datos_anteriores ->> 'estado'  AS estado_antes,
       b.datos_nuevos     ->> 'estado'  AS estado_despues
FROM bitacora_auditoria b, marca_bitacora m
WHERE b.bitacora_id > m.ultimo
ORDER BY b.bitacora_id;

-- P14: exactamente un evento de especies (el del administrador).
SELECT count(*) AS eventos_especies_p14
FROM bitacora_auditoria b, marca_bitacora m
WHERE b.bitacora_id > m.ultimo AND b.tabla = 'especies';

-- Se regresa el estatus original (queda como otro evento del administrador).
UPDATE especies SET estatus = 'Nativa' WHERE slug = 'paloma-alas-blancas';

-- ---------------------------------------------------------------------
-- 6.2 Falla SQL provocada (violación de CHECK) → ERROR ESPERADO 23514
-- ---------------------------------------------------------------------
UPDATE especies SET total_registros = -1 WHERE slug = 'cardenal-rojo';
-- Tipos de falla (para el reporte):
--  · Falla SQL (de transacción): una sentencia viola una regla; PostgreSQL
--    la rechaza y deshace solo esa transacción (como la de arriba o P06).
--  · Falla del sistema: se cae el servidor o la máquina; al reiniciar,
--    PostgreSQL reaplica el WAL desde el último checkpoint: lo confirmado
--    se conserva y lo no confirmado se descarta.
--  · Falla del medio: se daña el disco; el WAL local no basta y se recupera
--    desde el respaldo (pg_dump) o con archivado de WAL.

-- ---------------------------------------------------------------------
-- 6.3 P08 · Respaldo y restauración (se ejecuta en la terminal o en DBeaver)
-- ---------------------------------------------------------------------
-- Terminal (desde la carpeta db/):
--   pg_dump    -U postgres -h localhost -Fc -f respaldo/vuela_db.dump vuela_db
--   createdb   -U postgres -h localhost vuela_restore        (si no existe)
--   pg_restore -U postgres -h localhost -d vuela_restore --clean --if-exists respaldo/vuela_db.dump
-- DBeaver: clic derecho en vuela_db → Herramientas → Respaldo (formato Custom);
--          clic derecho en vuela_restore → Herramientas → Restaurar.
-- Verificación: correr la sección 4 de 07_validaciones.sql en vuela_db y en
-- vuela_restore; los conteos y la huella deben ser iguales.
-- Nota: el respaldo guarda los GRANT pero no crea el rol vuela_invitado; en el
-- mismo servidor ya existe. En otro servidor, crear el rol antes de restaurar.

-- ---------------------------------------------------------------------
-- 6.4 Copia sombra de especies
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS especies_sombra;
CREATE TABLE especies_sombra AS SELECT * FROM especies;

-- Error humano: un UPDATE sin WHERE borra los textos de todas las fichas.
UPDATE especies SET descripcion = NULL, habitat = NULL;
SELECT count(*) AS fichas_sin_texto FROM especies WHERE descripcion IS NULL;

-- Recuperación desde la copia sombra (solo columnas de catálogo; el contador
-- se deja como está porque es el vigente).
UPDATE especies e
SET descripcion = s.descripcion,
    habitat     = s.habitat
FROM especies_sombra s
WHERE s.especie_id = e.especie_id;

-- Verificación: 0 diferencias entre especies y su copia en las columnas de catálogo.
SELECT count(*) AS diferencias
FROM especies e JOIN especies_sombra s USING (especie_id)
WHERE (e.slug, e.nombre_comun, e.nombre_cientifico, e.estatus, e.clase_yolo,
       e.descripcion, e.habitat, e.region, e.foto_url)
      IS DISTINCT FROM
      (s.slug, s.nombre_comun, s.nombre_cientifico, s.estatus, s.clase_yolo,
       s.descripcion, s.habitat, s.region, s.foto_url);

-- ---------------------------------------------------------------------
-- 6.5 WAL vs. bitácora de auditoría
--     El WAL registra cada cambio físico (para recuperar tras un fallo);
--     la bitácora registra eventos de negocio (quién hizo qué).
-- ---------------------------------------------------------------------
SHOW wal_level;
DROP TABLE IF EXISTS marca_wal;
CREATE TEMP TABLE marca_wal AS SELECT pg_current_wal_lsn() AS lsn_antes;

UPDATE sitios SET descripcion = descripcion WHERE nombre = 'Otro';   -- un cambio cualquiera

SELECT m.lsn_antes,
       pg_current_wal_lsn()                           AS lsn_despues,
       pg_wal_lsn_diff(pg_current_wal_lsn(), m.lsn_antes) AS bytes_de_wal_escritos,
       pg_walfile_name(pg_current_wal_lsn())           AS archivo_wal_actual
FROM marca_wal m;

-- Resumen final de la bitácora por tabla y operación.
SELECT tabla, operacion, count(*) AS eventos
FROM bitacora_auditoria
GROUP BY tabla, operacion
ORDER BY tabla, operacion;
