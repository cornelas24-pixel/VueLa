-- =====================================================================
-- VueLa · Base de Datos II · UABCS
-- 05_sesion_A.sql — SESIÓN A de las pruebas de concurrencia (P09 a P12)
-- Basado en: Documento de diseño v2, secciones 9 y 10 (Retos 7, 8 y 9).
--
-- CÓMO SE USA
--  · Abrir este archivo y 06_sesion_B.sql en dos editores de DBeaver, cada
--    uno con su propia conexión a vuela_db y en modo auto-commit (las
--    transacciones se abren con BEGIN explícito).
--  · Ejecutar los PASOS en orden numérico, alternando: el 01 está aquí, el 02
--    en la sesión B, etc. Seleccionar el bloque completo del paso y ejecutar
--    con Alt+X.
--  · «(espera)» = esa sentencia se queda bloqueada; seguir con el siguiente
--    paso en la otra sesión.
--  · Se asume la base tal como queda después de 01 → 02 → 03 → 07 → 04.
--    Ids usados: avistamientos 1, 2, 6, 12, 13 · usuarios 1 Biólogo 1,
--    2 Biólogo 2, 4 Turista 2 (4 pendientes), 5 Turista 3 (4 pendientes).
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 01 · Sesión A — verificar que son dos sesiones distintas
-- ---------------------------------------------------------------------
SET timezone = 'America/Mazatlan';
SELECT pg_backend_pid() AS pid_sesion_a, current_setting('transaction_isolation') AS aislamiento;


-- =====================================================================
-- P09 · LECTURA NO REPETIBLE Y FANTASMA (Reto 7)
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 03 · Sesión A — READ COMMITTED: primera lectura
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT total_registros AS cardenal_total FROM especies WHERE slug = 'cardenal-rojo';
SELECT count(*) AS avistamientos_malecon FROM avistamientos
WHERE sitio_id = (SELECT sitio_id FROM sitios WHERE nombre = 'Malecón');

-- ---------------------------------------------------------------------
-- PASO 05 · Sesión A — READ COMMITTED: misma lectura después del COMMIT de B
-- Resultado: ambos valores cambiaron dentro de la MISMA transacción.
--   total_registros → lectura no repetible · count(*) → fantasma
-- ---------------------------------------------------------------------
SELECT total_registros AS cardenal_total FROM especies WHERE slug = 'cardenal-rojo';
SELECT count(*) AS avistamientos_malecon FROM avistamientos
WHERE sitio_id = (SELECT sitio_id FROM sitios WHERE nombre = 'Malecón');
COMMIT;

-- ---------------------------------------------------------------------
-- PASO 06 · Sesión A — REPEATABLE READ: primera lectura
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT total_registros AS cardenal_total FROM especies WHERE slug = 'cardenal-rojo';
SELECT count(*) AS avistamientos_malecon FROM avistamientos
WHERE sitio_id = (SELECT sitio_id FROM sitios WHERE nombre = 'Malecón');

-- ---------------------------------------------------------------------
-- PASO 08 · Sesión A — REPEATABLE READ: misma lectura → MISMOS valores
-- (la transacción ve la foto tomada en su primera consulta). Después del
-- COMMIT ya se ve el cambio de B.
-- ---------------------------------------------------------------------
SELECT total_registros AS cardenal_total FROM especies WHERE slug = 'cardenal-rojo';
SELECT count(*) AS avistamientos_malecon FROM avistamientos
WHERE sitio_id = (SELECT sitio_id FROM sitios WHERE nombre = 'Malecón');
COMMIT;
SELECT total_registros AS cardenal_total_tras_commit FROM especies WHERE slug = 'cardenal-rojo';


-- =====================================================================
-- LECTURA SUCIA (Reto 7): READ UNCOMMITTED se comporta como READ COMMITTED
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 09 · Sesión A
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL READ UNCOMMITTED;
SHOW transaction_isolation;
SELECT count(*) AS avistamientos_malecon FROM avistamientos
WHERE sitio_id = (SELECT sitio_id FROM sitios WHERE nombre = 'Malecón');

-- ---------------------------------------------------------------------
-- PASO 11 · Sesión A — B insertó pero NO confirmó: A no lo ve (sin lectura sucia)
-- ---------------------------------------------------------------------
SELECT count(*) AS avistamientos_malecon FROM avistamientos
WHERE sitio_id = (SELECT sitio_id FROM sitios WHERE nombre = 'Malecón');
COMMIT;


-- =====================================================================
-- ACTUALIZACIÓN PERDIDA (Reto 7) sobre especies.total_registros
-- La tabla temporal «lectura» simula la memoria de la aplicación:
-- leer el contador, calcular +1 y escribir el valor calculado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 13 · Sesión A — lee el contador
-- ---------------------------------------------------------------------
BEGIN;
DROP TABLE IF EXISTS lectura;
CREATE TEMP TABLE lectura AS
SELECT total_registros AS valor FROM especies WHERE slug = 'zopilote-aura';
SELECT valor AS zopilote_leido_por_a FROM lectura;

-- ---------------------------------------------------------------------
-- PASO 15 · Sesión A — escribe valor_leído + 1 y confirma
-- ---------------------------------------------------------------------
UPDATE especies SET total_registros = (SELECT valor FROM lectura) + 1
WHERE slug = 'zopilote-aura';
COMMIT;

-- ---------------------------------------------------------------------
-- PASO 17 · Sesión A — resultado: hubo dos sumas pero el contador solo subió 1
-- ---------------------------------------------------------------------
SELECT total_registros AS zopilote_final FROM especies WHERE slug = 'zopilote-aura';

-- CORRECCIÓN con SELECT … FOR UPDATE
-- ---------------------------------------------------------------------
-- PASO 18 · Sesión A — lee bloqueando la fila
-- ---------------------------------------------------------------------
BEGIN;
SELECT total_registros FROM especies WHERE slug = 'zopilote-aura' FOR UPDATE;
DROP TABLE IF EXISTS lectura;
CREATE TEMP TABLE lectura AS
SELECT total_registros AS valor FROM especies WHERE slug = 'zopilote-aura';
SELECT valor AS zopilote_leido_por_a FROM lectura;

-- ---------------------------------------------------------------------
-- PASO 20 · Sesión A — escribe y confirma (libera a B)
-- ---------------------------------------------------------------------
UPDATE especies SET total_registros = (SELECT valor FROM lectura) + 1
WHERE slug = 'zopilote-aura';
COMMIT;

-- ---------------------------------------------------------------------
-- PASO 22 · Sesión A — ahora sí subió 2. Después se regresa el contador a
-- su valor real (estas pruebas lo movieron a mano) y se comprueba RN5.
-- En la base real no hace falta FOR UPDATE: trg_contar_avistamiento usa
-- UPDATE … SET total = total + 1, que es atómico.
-- ---------------------------------------------------------------------
SELECT total_registros AS zopilote_final FROM especies WHERE slug = 'zopilote-aura';
UPDATE especies e
SET total_registros = (SELECT count(*) FROM avistamientos a WHERE a.especie_id = e.especie_id)
WHERE slug = 'zopilote-aura';
SELECT e.total_registros, (SELECT count(*) FROM avistamientos a WHERE a.especie_id = e.especie_id) AS conteo_real
FROM especies e WHERE slug = 'zopilote-aura';


-- =====================================================================
-- P10 · FILA BLOQUEADA (Reto 8)
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 23 · Sesión A — bloquea el avistamiento 13 (pendiente)
-- ---------------------------------------------------------------------
BEGIN;
SELECT avistamiento_id, estado FROM avistamientos WHERE avistamiento_id = 13 FOR UPDATE;

-- ---------------------------------------------------------------------
-- PASO 25 · Sesión A — evidencia de la espera de B y COMMIT (B continúa)
-- ---------------------------------------------------------------------
SELECT pid, state, wait_event_type, wait_event, pg_blocking_pids(pid) AS bloqueado_por,
       left(query, 60) AS consulta
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid() AND backend_type = 'client backend';
COMMIT;


-- =====================================================================
-- INTERFERENCIA (a) / RN3: dos biólogos revisan el mismo pendiente a la vez
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 27 · Sesión A — Biólogo 1 valida el #12 (sin confirmar todavía)
-- ---------------------------------------------------------------------
BEGIN;
CALL sp_revisar_avistamiento(12, 1, 'validado', 'Revisión de la sesión A.');

-- ---------------------------------------------------------------------
-- PASO 29 · Sesión A — confirma; B recibe el error de RN3
-- ---------------------------------------------------------------------
COMMIT;


-- =====================================================================
-- P11 · DEADLOCK Y SU PREVENCIÓN (Reto 8)
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 31 · Sesión A — bloquea el avistamiento 1
-- ---------------------------------------------------------------------
BEGIN;
SELECT avistamiento_id FROM avistamientos WHERE avistamiento_id = 1 FOR UPDATE;

-- ---------------------------------------------------------------------
-- PASO 33 · Sesión A — pide el 2 (lo tiene B)  (espera)
-- ---------------------------------------------------------------------
SELECT avistamiento_id FROM avistamientos WHERE avistamiento_id = 2 FOR UPDATE;

-- ---------------------------------------------------------------------
-- PASO 36 · Sesión A — al abortar B, A obtiene el 2; confirma
-- (Si PostgreSQL hubiera elegido a A como víctima, este COMMIT termina en
--  ROLLBACK: el resultado de la prueba es el mismo, una sesión recibe 40P01.)
-- ---------------------------------------------------------------------
COMMIT;

-- PREVENCIÓN: ambas sesiones bloquean en el mismo orden (por avistamiento_id)
-- ---------------------------------------------------------------------
-- PASO 37 · Sesión A
-- ---------------------------------------------------------------------
BEGIN;
SELECT avistamiento_id FROM avistamientos
WHERE avistamiento_id IN (1, 2) ORDER BY avistamiento_id FOR UPDATE;

-- ---------------------------------------------------------------------
-- PASO 39 · Sesión A — confirma; B obtiene ambos sin deadlock
-- ---------------------------------------------------------------------
COMMIT;


-- =====================================================================
-- P12 · MARCAS DE TIEMPO (Reto 9) con ts_avistamiento
-- Caso: el mismo avistamiento (#6) se corrigió en dos celulares sin conexión.
-- Regla: se acepta la operación solo si su marca es POSTERIOR a la última
-- aceptada; si no, se rechaza (40001) y no se aplica nada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 42 · Sesión A — llega tarde una corrección con marca 11:00
-- → ERROR ESPERADO 40001 (marca anterior a la ya aceptada de B, 11:05)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO ts_avistamiento AS t (avistamiento_id, ultima_marca)
    VALUES (6, '2026-11-11 11:00:00-07')
    ON CONFLICT (avistamiento_id) DO UPDATE
        SET ultima_marca = EXCLUDED.ultima_marca
        WHERE t.ultima_marca < EXCLUDED.ultima_marca;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Marca de tiempo 2026-11-11 11:00 no es posterior a la última aceptada; operación rechazada.'
            USING ERRCODE = 'serialization_failure';
    END IF;
    UPDATE avistamientos SET latitud = 24.320500, longitud = -110.325300 WHERE avistamiento_id = 6;
END $$;

-- ---------------------------------------------------------------------
-- PASO 43 · Sesión A — decisión verificable: queda la marca y la ubicación de B
-- ---------------------------------------------------------------------
SELECT * FROM ts_avistamiento WHERE avistamiento_id = 6;
SELECT avistamiento_id, latitud, longitud FROM avistamientos WHERE avistamiento_id = 6;


-- =====================================================================
-- P12 · SERIALIZABLE con RN6 (Reto 9)
-- Primero se muestra el problema en READ COMMITTED y luego la solución.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 44 · Sesión A — READ COMMITTED: Turista 2 (4 pendientes) registra
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL READ COMMITTED;
CALL sp_registrar_avistamiento(4, 1, 1, 24.166400, -110.312300, '2026-11-11 12:00:00-07', 'manual');

-- ---------------------------------------------------------------------
-- PASO 46 · Sesión A — confirma
-- ---------------------------------------------------------------------
COMMIT;

-- ---------------------------------------------------------------------
-- PASO 48 · Sesión A — limpieza: se borran los dos registros de la prueba
-- (pendientes y sin revisión) para regresar a Turista 2 a 4 pendientes.
-- ---------------------------------------------------------------------
DELETE FROM avistamientos
WHERE usuario_id = 4
  AND fecha_hora IN ('2026-11-11 12:00:00-07', '2026-11-11 12:01:00-07');
SELECT count(*) AS pendientes_turista_2 FROM avistamientos WHERE usuario_id = 4 AND estado = 'pendiente';

-- ---------------------------------------------------------------------
-- PASO 49 · Sesión A — SERIALIZABLE: Turista 3 (4 pendientes) registra
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL SERIALIZABLE;
CALL sp_registrar_avistamiento(5, 1, 4, 24.321600, -110.324000, '2026-11-11 12:10:00-07', 'manual');

-- ---------------------------------------------------------------------
-- PASO 51 · Sesión A — confirma primero: gana
-- ---------------------------------------------------------------------
COMMIT;

-- Al terminar: correr 07_validaciones.sql (todo debe salir en 0 / OK).
