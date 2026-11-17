-- =====================================================================
-- VueLa · Base de Datos II · UABCS
-- 06_sesion_B.sql — SESIÓN B de las pruebas de concurrencia (P09 a P12)
-- Basado en: Documento de diseño v2, secciones 9 y 10 (Retos 7, 8 y 9).
--
-- Ver instrucciones en 05_sesion_A.sql. Ejecutar los PASOS en orden numérico
-- alternando con la sesión A. «(espera)» = la sentencia se queda bloqueada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 02 · Sesión B — debe mostrar un pid distinto al de la sesión A
-- ---------------------------------------------------------------------
SET timezone = 'America/Mazatlan';
SELECT pg_backend_pid() AS pid_sesion_b, current_setting('transaction_isolation') AS aislamiento;


-- =====================================================================
-- P09 · LECTURA NO REPETIBLE Y FANTASMA
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 04 · Sesión B — Biólogo 1 registra un cardenal en el Malecón (auto-commit)
-- ---------------------------------------------------------------------
CALL sp_registrar_avistamiento(1, 2, 1, 24.166900, -110.312100, '2026-11-11 10:00:00-07', 'camara',
    NULL, false, 2, 0.930, 0.30, 0.20, 0.40, 0.50, 'vuela-v1');

-- ---------------------------------------------------------------------
-- PASO 07 · Sesión B — otro registro mientras A está en REPEATABLE READ
-- ---------------------------------------------------------------------
CALL sp_registrar_avistamiento(1, 2, 1, 24.166950, -110.312150, '2026-11-11 10:05:00-07', 'camara',
    NULL, false, 2, 0.918, 0.28, 0.22, 0.42, 0.48, 'vuela-v1');


-- =====================================================================
-- LECTURA SUCIA
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 10 · Sesión B — inserta SIN confirmar
-- ---------------------------------------------------------------------
BEGIN;
CALL sp_registrar_avistamiento(2, 8, 1, 24.166300, -110.312500, '2026-11-11 10:10:00-07', 'camara',
    NULL, false, 8, 0.881, 0.25, 0.30, 0.35, 0.40, 'vuela-v1');

-- ---------------------------------------------------------------------
-- PASO 12 · Sesión B — deshace: el dato nunca existió para nadie más
-- ---------------------------------------------------------------------
ROLLBACK;


-- =====================================================================
-- ACTUALIZACIÓN PERDIDA
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 14 · Sesión B — lee el MISMO valor que A
-- ---------------------------------------------------------------------
BEGIN;
DROP TABLE IF EXISTS lectura;
CREATE TEMP TABLE lectura AS
SELECT total_registros AS valor FROM especies WHERE slug = 'zopilote-aura';
SELECT valor AS zopilote_leido_por_b FROM lectura;

-- ---------------------------------------------------------------------
-- PASO 16 · Sesión B — escribe valor_leído + 1: pisa la suma de A
-- ---------------------------------------------------------------------
UPDATE especies SET total_registros = (SELECT valor FROM lectura) + 1
WHERE slug = 'zopilote-aura';
COMMIT;

-- CORRECCIÓN con SELECT … FOR UPDATE
-- ---------------------------------------------------------------------
-- PASO 19 · Sesión B — intenta leer bloqueando  (espera)
-- ---------------------------------------------------------------------
BEGIN;
SELECT total_registros FROM especies WHERE slug = 'zopilote-aura' FOR UPDATE;

-- ---------------------------------------------------------------------
-- PASO 21 · Sesión B — ya liberado, lee el valor NUEVO, escribe y confirma
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS lectura;
CREATE TEMP TABLE lectura AS
SELECT total_registros AS valor FROM especies WHERE slug = 'zopilote-aura';
SELECT valor AS zopilote_leido_por_b FROM lectura;
UPDATE especies SET total_registros = (SELECT valor FROM lectura) + 1
WHERE slug = 'zopilote-aura';
COMMIT;


-- =====================================================================
-- P10 · FILA BLOQUEADA
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 24 · Sesión B — Biólogo 2 intenta revisar el #13  (espera)
-- ---------------------------------------------------------------------
CALL sp_revisar_avistamiento(13, 2, 'validado', 'Revisado cuando la sesión A liberó el bloqueo.');

-- ---------------------------------------------------------------------
-- PASO 26 · Sesión B — continuó después del COMMIT de A
-- ---------------------------------------------------------------------
SELECT a.avistamiento_id, a.estado, r.revisor_id, r.revisado_en
FROM avistamientos a JOIN revisiones r USING (avistamiento_id)
WHERE a.avistamiento_id = 13;


-- =====================================================================
-- INTERFERENCIA (a) / RN3
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 28 · Sesión B — Biólogo 2 rechaza el #12 al mismo tiempo  (espera)
-- Cuando A confirme → ERROR ESPERADO: «RN3: el avistamiento 12 ya fue revisado»
-- ---------------------------------------------------------------------
CALL sp_revisar_avistamiento(12, 2, 'rechazado', 'Revisión de la sesión B.');

-- ---------------------------------------------------------------------
-- PASO 30 · Sesión B — la base conservó una sola revisión (la de A)
-- ---------------------------------------------------------------------
SELECT r.revision_id, r.avistamiento_id, r.revisor_id, r.decision, a.estado
FROM revisiones r JOIN avistamientos a USING (avistamiento_id)
WHERE r.avistamiento_id = 12;


-- =====================================================================
-- P11 · DEADLOCK Y SU PREVENCIÓN
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 32 · Sesión B — bloquea el avistamiento 2
-- ---------------------------------------------------------------------
BEGIN;
SELECT avistamiento_id FROM avistamientos WHERE avistamiento_id = 2 FOR UPDATE;

-- ---------------------------------------------------------------------
-- PASO 34 · Sesión B — pide el 1 (lo tiene A): ciclo de espera
-- → ERROR ESPERADO 40P01 deadlock detected (tras ~1 s, deadlock_timeout)
-- ---------------------------------------------------------------------
SELECT avistamiento_id FROM avistamientos WHERE avistamiento_id = 1 FOR UPDATE;

-- ---------------------------------------------------------------------
-- PASO 35 · Sesión B — termina la transacción abortada
-- ---------------------------------------------------------------------
ROLLBACK;

-- PREVENCIÓN: mismo orden de bloqueo que A
-- ---------------------------------------------------------------------
-- PASO 38 · Sesión B  (espera)
-- ---------------------------------------------------------------------
BEGIN;
SELECT avistamiento_id FROM avistamientos
WHERE avistamiento_id IN (1, 2) ORDER BY avistamiento_id FOR UPDATE;

-- ---------------------------------------------------------------------
-- PASO 40 · Sesión B — obtuvo ambos sin deadlock; confirma
-- ---------------------------------------------------------------------
COMMIT;


-- =====================================================================
-- P12 · MARCAS DE TIEMPO con ts_avistamiento
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 41 · Sesión B — sincroniza primero su corrección con marca 11:05: se acepta
-- ---------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO ts_avistamiento AS t (avistamiento_id, ultima_marca)
    VALUES (6, '2026-11-11 11:05:00-07')
    ON CONFLICT (avistamiento_id) DO UPDATE
        SET ultima_marca = EXCLUDED.ultima_marca
        WHERE t.ultima_marca < EXCLUDED.ultima_marca;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Marca de tiempo 2026-11-11 11:05 no es posterior a la última aceptada; operación rechazada.'
            USING ERRCODE = 'serialization_failure';
    END IF;
    UPDATE avistamientos SET latitud = 24.321100, longitud = -110.324600 WHERE avistamiento_id = 6;
    RAISE NOTICE 'Marca 11:05 aceptada para el avistamiento 6.';
END $$;


-- =====================================================================
-- P12 · SERIALIZABLE con RN6
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 45 · Sesión B — READ COMMITTED: Turista 2 registra al mismo tiempo.
-- No ve el registro sin confirmar de A, cuenta 4 y también inserta.
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL READ COMMITTED;
CALL sp_registrar_avistamiento(4, 5, 2, 24.162800, -110.361800, '2026-11-11 12:01:00-07', 'manual');

-- ---------------------------------------------------------------------
-- PASO 47 · Sesión B — confirma: Turista 2 queda con 6 pendientes (¡RN6 violada!)
-- ---------------------------------------------------------------------
COMMIT;
SELECT count(*) AS pendientes_turista_2 FROM avistamientos WHERE usuario_id = 4 AND estado = 'pendiente';

-- ---------------------------------------------------------------------
-- PASO 50 · Sesión B — SERIALIZABLE: Turista 3 registra al mismo tiempo que A
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL SERIALIZABLE;
CALL sp_registrar_avistamiento(5, 7, 4, 24.321300, -110.324400, '2026-11-11 12:11:00-07', 'manual');

-- ---------------------------------------------------------------------
-- PASO 52 · Sesión B — confirma después de A
-- → ERROR ESPERADO 40001 could not serialize access due to read/write
--   dependencies among transactions. PostgreSQL deshace a B.
-- ---------------------------------------------------------------------
COMMIT;

-- ---------------------------------------------------------------------
-- PASO 53 · Sesión B — la aplicación reintenta: ahora ve 5 pendientes y RN6
-- la rechaza → ERROR ESPERADO (RN6). Turista 3 queda en 5, nunca en 6.
-- ---------------------------------------------------------------------
CALL sp_registrar_avistamiento(5, 7, 4, 24.321300, -110.324400, '2026-11-11 12:11:00-07', 'manual');
SELECT count(*) AS pendientes_turista_3 FROM avistamientos WHERE usuario_id = 5 AND estado = 'pendiente';

-- Al terminar: correr 07_validaciones.sql (todo debe salir en 0 / OK).
