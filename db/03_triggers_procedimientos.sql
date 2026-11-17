-- =====================================================================
-- VueLa · Base de Datos II · UABCS
-- 03_triggers_procedimientos.sql — Triggers, funciones y procedimientos,
-- con pruebas de éxito y rechazo (Reto 3.4); al final, vistas públicas y
-- rol vuela_invitado (extra, RN8 / P13).
-- Basado en: Documento de diseño v2, secciones 4, 5 y 6.
--
-- Se ejecuta después de 01 y 02. Las pruebas usan los id que deja 02 en una
-- base recién creada:
--   usuarios : 1 Biólogo 1 · 2 Biólogo 2 · 3 Turista 1 · 4 Turista 2
--              5 Turista 3 · 6 Turista 4 · 7 Turista 5 (inactivo)
--   especies : 1 calandria · 2 cardenal · 3 carpintero · 4 pinzón · 5 matraca
--              6 caracara · 7 zopilote · 8 paloma · 9 cuicacoche · 10 tortolita
--   sitios   : 1 Malecón · 2 Estero El Mogote · 3 Cerro de la Calavera
--              4 Playa Balandra · 5 Playa El Tesoro · 6 Otro
--   avistamientos 1 a 15 (pendientes: 5, 6, 11, 12, 13, 14, 15)
-- =====================================================================

-- Fechas en hora de La Paz, B.C.S. (solo afecta cómo se muestran).
SET timezone = 'America/Mazatlan';

-- =====================================================================
-- PARTE A. OBJETOS
-- =====================================================================

-- ---------------------------------------------------------------------
-- A1. trg_validar_revision — BEFORE INSERT en revisiones (RN3 y RN4)
--     Bloquea la fila del avistamiento (FOR UPDATE): si dos biólogos
--     revisan a la vez, el segundo espera y, al continuar, ya ve el
--     estado nuevo y es rechazado.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_revision()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_autor   INT;
    v_estado  VARCHAR(10);
    v_rol     VARCHAR(20);
    v_activo  BOOLEAN;
BEGIN
    SELECT usuario_id, estado INTO v_autor, v_estado
    FROM avistamientos
    WHERE avistamiento_id = NEW.avistamiento_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El avistamiento % no existe.', NEW.avistamiento_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF v_estado <> 'pendiente' THEN
        RAISE EXCEPTION 'RN3: el avistamiento % ya fue revisado (estado: %).', NEW.avistamiento_id, v_estado;
    END IF;

    SELECT r.nombre, u.activo INTO v_rol, v_activo
    FROM usuarios u JOIN roles r ON r.rol_id = u.rol_id
    WHERE u.usuario_id = NEW.revisor_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El revisor % no existe.', NEW.revisor_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF v_rol <> 'biologo' OR NOT v_activo THEN
        RAISE EXCEPTION 'RN4: solo un biólogo activo puede revisar (usuario %, rol %, activo %).',
            NEW.revisor_id, v_rol, v_activo;
    END IF;

    IF v_autor = NEW.revisor_id THEN
        RAISE EXCEPTION 'RN4: el biólogo % no puede revisar su propio avistamiento (%).',
            NEW.revisor_id, NEW.avistamiento_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_revision ON revisiones;
CREATE TRIGGER trg_validar_revision
    BEFORE INSERT ON revisiones
    FOR EACH ROW EXECUTE FUNCTION fn_validar_revision();

-- ---------------------------------------------------------------------
-- A2. trg_aplicar_revision — AFTER INSERT en revisiones
--     Copia la decisión al estado del avistamiento.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_aplicar_revision()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE avistamientos
    SET estado = NEW.decision
    WHERE avistamiento_id = NEW.avistamiento_id;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_aplicar_revision ON revisiones;
CREATE TRIGGER trg_aplicar_revision
    AFTER INSERT ON revisiones
    FOR EACH ROW EXECUTE FUNCTION fn_aplicar_revision();

-- ---------------------------------------------------------------------
-- A3. trg_proteger_estado — BEFORE UPDATE OF estado en avistamientos (RN4)
--     Solo deja pasar de pendiente a validado/rechazado cuando ya existe una
--     revisión con esa misma decisión. Además (refuerzo de RN4 en INSERT):
--     un avistamiento nuevo solo puede entrar como pendiente.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_proteger_estado()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado <> 'pendiente' THEN
            RAISE EXCEPTION 'RN4: un avistamiento nuevo entra como pendiente; el estado solo cambia mediante una revisión.';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF OLD.estado <> 'pendiente' THEN
        RAISE EXCEPTION 'RN4: el avistamiento % ya está % y no puede cambiar a %.',
            OLD.avistamiento_id, OLD.estado, NEW.estado;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM revisiones
                   WHERE avistamiento_id = NEW.avistamiento_id
                     AND decision = NEW.estado) THEN
        RAISE EXCEPTION 'RN4: el estado del avistamiento % solo cambia mediante una revisión.',
            OLD.avistamiento_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_estado ON avistamientos;
CREATE TRIGGER trg_proteger_estado
    BEFORE INSERT OR UPDATE OF estado ON avistamientos
    FOR EACH ROW EXECUTE FUNCTION fn_proteger_estado();

-- ---------------------------------------------------------------------
-- A4. trg_contar_avistamiento — AFTER INSERT / DELETE en avistamientos (RN5)
--     total = total ± 1 de forma atómica (sin leer y luego escribir), sin
--     importar el estado. También cubre el cambio de especie_id en un UPDATE
--     para que el contador siga coincidiendo con el conteo real.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_contar_avistamiento()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.especie_id = OLD.especie_id THEN
        RETURN NULL;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        UPDATE especies SET total_registros = total_registros + 1
        WHERE especie_id = NEW.especie_id;
    END IF;

    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        UPDATE especies SET total_registros = total_registros - 1
        WHERE especie_id = OLD.especie_id;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_contar_avistamiento ON avistamientos;
CREATE TRIGGER trg_contar_avistamiento
    AFTER INSERT OR DELETE OR UPDATE OF especie_id ON avistamientos
    FOR EACH ROW EXECUTE FUNCTION fn_contar_avistamiento();

-- ---------------------------------------------------------------------
-- A5. trg_auditoria — AFTER INSERT / UPDATE / DELETE en avistamientos,
--     revisiones, usuarios, especies y sitios.
--     TG_ARGV[0] = nombre de la columna llave. usuario_db = current_user
--     (default de la tabla); usuario_app_id = vuela.usuario_id si la sesión
--     lo fijó con SET LOCAL / set_config(..., true).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auditoria()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_anterior JSONB;
    v_nuevo    JSONB;
BEGIN
    -- El hash de la contraseña nunca se copia a la bitácora.
    IF TG_OP <> 'INSERT' THEN v_anterior := to_jsonb(OLD) - 'contrasena_hash'; END IF;
    IF TG_OP <> 'DELETE' THEN v_nuevo    := to_jsonb(NEW) - 'contrasena_hash'; END IF;

    INSERT INTO bitacora_auditoria (tabla, operacion, registro_id, usuario_app_id,
                                    datos_anteriores, datos_nuevos)
    VALUES (TG_TABLE_NAME,
            TG_OP,
            (COALESCE(v_nuevo, v_anterior) ->> TG_ARGV[0])::INT,
            NULLIF(current_setting('vuela.usuario_id', true), '')::INT,
            v_anterior,
            v_nuevo);
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_auditoria ON avistamientos;
CREATE TRIGGER trg_auditoria
    AFTER INSERT OR UPDATE OR DELETE ON avistamientos
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria('avistamiento_id');

DROP TRIGGER IF EXISTS trg_auditoria ON revisiones;
CREATE TRIGGER trg_auditoria
    AFTER INSERT OR UPDATE OR DELETE ON revisiones
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria('revision_id');

DROP TRIGGER IF EXISTS trg_auditoria ON usuarios;
CREATE TRIGGER trg_auditoria
    AFTER INSERT OR UPDATE OR DELETE ON usuarios
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria('usuario_id');

DROP TRIGGER IF EXISTS trg_auditoria ON sitios;
CREATE TRIGGER trg_auditoria
    AFTER INSERT OR UPDATE OR DELETE ON sitios
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria('sitio_id');

-- En especies solo columnas de catálogo: el contador (total_registros) no
-- genera eventos para no llenar la bitácora.
DROP TRIGGER IF EXISTS trg_auditoria ON especies;
CREATE TRIGGER trg_auditoria
    AFTER INSERT OR DELETE
       OR UPDATE OF slug, nombre_comun, nombre_cientifico, estatus, clase_yolo,
                    descripcion, habitat, region, foto_url
    ON especies
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria('especie_id');

-- ---------------------------------------------------------------------
-- A6. sp_registrar_avistamiento — operación compuesta (sección 5)
--     Valida, fija vuela.usuario_id, inserta avistamiento y detección.
--     El contador y la bitácora los mueven los triggers. Si algo falla,
--     todo el CALL se revierte (no hay COMMIT dentro: se puede usar dentro
--     de una transacción con SAVEPOINT).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_avistamiento(
    p_usuario_id           INT,
    p_especie_id           INT,
    p_sitio_id             INT,
    p_latitud              NUMERIC,
    p_longitud             NUMERIC,
    p_fecha_hora           TIMESTAMPTZ DEFAULT now(),
    p_origen               VARCHAR     DEFAULT 'camara',
    p_uuid_cliente         UUID        DEFAULT NULL,
    p_ubicacion_aprox      BOOLEAN     DEFAULT false,
    p_especie_predicha_id  INT         DEFAULT NULL,
    p_confianza            NUMERIC     DEFAULT NULL,
    p_caja_x               NUMERIC     DEFAULT NULL,
    p_caja_y               NUMERIC     DEFAULT NULL,
    p_caja_w               NUMERIC     DEFAULT NULL,
    p_caja_h               NUMERIC     DEFAULT NULL,
    p_modelo_version       VARCHAR     DEFAULT NULL,
    INOUT p_avistamiento_id INT        DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_activo         BOOLEAN;
    v_rol            VARCHAR(20);
    v_pendientes     INT;
    v_con_deteccion  BOOLEAN;
    v_det_completa   BOOLEAN;
BEGIN
    -- Usuario activo
    SELECT u.activo, r.nombre INTO v_activo, v_rol
    FROM usuarios u JOIN roles r ON r.rol_id = u.rol_id
    WHERE u.usuario_id = p_usuario_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario % no existe.', p_usuario_id USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF NOT v_activo THEN
        RAISE EXCEPTION 'El usuario % está inactivo y no puede registrar avistamientos.', p_usuario_id;
    END IF;

    -- Especie y sitio existentes
    IF NOT EXISTS (SELECT 1 FROM especies WHERE especie_id = p_especie_id) THEN
        RAISE EXCEPTION 'La especie % no existe.', p_especie_id USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM sitios WHERE sitio_id = p_sitio_id) THEN
        RAISE EXCEPTION 'El sitio % no existe.', p_sitio_id USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- Coordenadas
    IF p_latitud IS NULL OR p_longitud IS NULL
       OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180 THEN
        RAISE EXCEPTION 'Coordenadas fuera de rango: (%, %).', p_latitud, p_longitud
            USING ERRCODE = 'check_violation';
    END IF;

    -- RN7: fecha no futura (misma tolerancia que el CHECK)
    IF p_fecha_hora > now() + INTERVAL '5 minutes' THEN
        RAISE EXCEPTION 'RN7: la fecha % está en el futuro.', p_fecha_hora
            USING ERRCODE = 'check_violation';
    END IF;

    -- Detección: obligatoria y completa solo para origen camara
    v_con_deteccion := COALESCE(p_especie_predicha_id, p_confianza, p_caja_x, p_caja_y, p_caja_w, p_caja_h) IS NOT NULL
                       OR p_modelo_version IS NOT NULL;
    v_det_completa  := p_especie_predicha_id IS NOT NULL AND p_confianza IS NOT NULL
                       AND p_caja_x IS NOT NULL AND p_caja_y IS NOT NULL
                       AND p_caja_w IS NOT NULL AND p_caja_h IS NOT NULL
                       AND p_modelo_version IS NOT NULL;
    IF p_origen = 'camara' AND NOT v_det_completa THEN
        RAISE EXCEPTION 'Un avistamiento de cámara requiere su detección completa (especie predicha, confianza, caja y versión del modelo).';
    END IF;
    IF p_origen <> 'camara' AND v_con_deteccion THEN
        RAISE EXCEPTION 'Solo los avistamientos de cámara llevan detección (origen recibido: %).', p_origen;
    END IF;

    -- RN6: un turista no puede tener más de 5 pendientes a la vez
    IF v_rol = 'turista' THEN
        SELECT count(*) INTO v_pendientes
        FROM avistamientos
        WHERE usuario_id = p_usuario_id AND estado = 'pendiente';
        IF v_pendientes >= 5 THEN
            RAISE EXCEPTION 'RN6: el turista % ya tiene % avistamientos pendientes (máximo 5).',
                p_usuario_id, v_pendientes;
        END IF;
    END IF;

    -- Usuario de la app para la bitácora (equivale a SET LOCAL vuela.usuario_id)
    PERFORM set_config('vuela.usuario_id', p_usuario_id::TEXT, true);

    INSERT INTO avistamientos (uuid_cliente, usuario_id, especie_id, sitio_id, fecha_hora,
                               origen, latitud, longitud, ubicacion_aprox)
    VALUES (COALESCE(p_uuid_cliente, gen_random_uuid()), p_usuario_id, p_especie_id, p_sitio_id,
            p_fecha_hora, p_origen, p_latitud, p_longitud, p_ubicacion_aprox)
    RETURNING avistamiento_id INTO p_avistamiento_id;

    IF p_origen = 'camara' THEN
        INSERT INTO detecciones (avistamiento_id, especie_predicha_id, confianza,
                                 caja_x, caja_y, caja_w, caja_h, modelo_version)
        VALUES (p_avistamiento_id, p_especie_predicha_id, p_confianza,
                p_caja_x, p_caja_y, p_caja_w, p_caja_h, p_modelo_version);
    END IF;

    RAISE NOTICE 'Avistamiento % registrado.', p_avistamiento_id;
END;
$$;

-- ---------------------------------------------------------------------
-- A7. sp_revisar_avistamiento (opcional en el diseño) — envuelve el INSERT
--     en revisiones con mensajes claros y fija vuela.usuario_id.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_revisar_avistamiento(
    p_avistamiento_id  INT,
    p_revisor_id       INT,
    p_decision         VARCHAR,
    p_comentario       VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_decision IS NULL OR p_decision NOT IN ('validado', 'rechazado') THEN
        RAISE EXCEPTION 'La decisión debe ser validado o rechazado (se recibió %).', p_decision
            USING ERRCODE = 'check_violation';
    END IF;

    PERFORM set_config('vuela.usuario_id', p_revisor_id::TEXT, true);

    INSERT INTO revisiones (avistamiento_id, revisor_id, decision, comentario)
    VALUES (p_avistamiento_id, p_revisor_id, p_decision, p_comentario);

    RAISE NOTICE 'Avistamiento % marcado como % por el usuario %.', p_avistamiento_id, p_decision, p_revisor_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'RN3: el avistamiento % ya tiene una revisión.', p_avistamiento_id
            USING ERRCODE = 'unique_violation';
END;
$$;


-- ---------------------------------------------------------------------
-- A8. Inicio de sesión
--     fn_registrar_usuario: crea una cuenta desde la app. Siempre como
--       turista; los biólogos los da de alta el administrador por SQL.
--     fn_verificar_credenciales: compara la contraseña con su hash bcrypt
--       dentro de la base. Devuelve el usuario o ninguna fila (correo o
--       contraseña incorrectos, o usuario inactivo).
--     Las sesiones (tabla sesiones) las abre y cierra el servidor.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_registrar_usuario(p_nombre TEXT, p_correo TEXT, p_contrasena TEXT)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_id INT;
BEGIN
    IF p_nombre IS NULL OR length(trim(p_nombre)) < 2 THEN
        RAISE EXCEPTION 'Escribe tu nombre (al menos 2 letras).' USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO usuarios (nombre, correo, rol_id, contrasena_hash)
    VALUES (trim(p_nombre), lower(trim(p_correo)),
            (SELECT rol_id FROM roles WHERE nombre = 'turista'),
            fn_hash_contrasena(p_contrasena))
    RETURNING usuario_id INTO v_id;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_verificar_credenciales(p_correo TEXT, p_contrasena TEXT)
RETURNS TABLE (usuario_id INT, nombre VARCHAR, rol VARCHAR)
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
    SELECT u.usuario_id, u.nombre, r.nombre
    FROM usuarios u
    JOIN roles r ON r.rol_id = u.rol_id
    WHERE lower(u.correo) = lower(trim(p_correo))
      AND u.activo
      AND u.contrasena_hash = crypt(p_contrasena, u.contrasena_hash);
$$;


-- =====================================================================
-- PARTE B. PRUEBAS (un caso exitoso y uno rechazado por objeto)
-- =====================================================================

-- ---------------------------------------------------------------------
-- B1. Estado inicial de los contadores que se van a mover
-- ---------------------------------------------------------------------
SELECT especie_id, slug, total_registros
FROM especies
WHERE especie_id IN (1, 4, 7, 10)
ORDER BY especie_id;

-- ---------------------------------------------------------------------
-- B2. sp_registrar_avistamiento — casos exitosos
-- ---------------------------------------------------------------------
-- Turista 2 registra un pinzón en el Malecón con su detección (queda como id 16).
CALL sp_registrar_avistamiento(
    p_usuario_id => 4, p_especie_id => 4, p_sitio_id => 1,
    p_latitud => 24.166950, p_longitud => -110.312010,
    p_fecha_hora => '2026-11-10 07:10:00-07', p_origen => 'camara',
    p_especie_predicha_id => 4, p_confianza => 0.890,
    p_caja_x => 0.30, p_caja_y => 0.25, p_caja_w => 0.35, p_caja_h => 0.40,
    p_modelo_version => 'vuela-v1');

-- Turista 3 registra dos más: uno de cámara (id 17) y uno manual sin detección (id 18).
-- Con esto Turista 3 llega a 5 pendientes (límite de RN6).
CALL sp_registrar_avistamiento(5, 1, 4, 24.321900, -110.323900, '2026-11-10 08:00:00-07', 'camara',
    NULL, false, 1, 0.845, 0.20, 0.22, 0.40, 0.45, 'vuela-v1');
CALL sp_registrar_avistamiento(5, 10, 2, 24.163300, -110.361900, '2026-11-10 08:30:00-07', 'manual');

-- Biólogo 1 también registra (id 19): sirve para probar que no puede revisar el suyo.
CALL sp_registrar_avistamiento(1, 7, 3, 24.187000, -110.299200, '2026-11-10 09:00:00-07', 'camara',
    NULL, false, 7, 0.962, 0.15, 0.10, 0.60, 0.55, 'vuela-v1');

-- El contador subió 1 por cada registro (pinzón, calandria, tortolita, zopilote).
SELECT especie_id, slug, total_registros
FROM especies
WHERE especie_id IN (1, 4, 7, 10)
ORDER BY especie_id;

-- ---------------------------------------------------------------------
-- B3. sp_registrar_avistamiento — casos rechazados (nada queda a medias)
-- ---------------------------------------------------------------------
SELECT count(*) AS avistamientos_antes FROM avistamientos;

SELECT * FROM fn_probar_rechazo('SP-a usuario inactivo (Turista 5)', $q$
    CALL sp_registrar_avistamiento(7, 2, 1, 24.1665, -110.3121, now(), 'ficha')
$q$, 'P0001')
UNION ALL
SELECT * FROM fn_probar_rechazo('SP-b RN6: sexto pendiente de Turista 3', $q$
    CALL sp_registrar_avistamiento(5, 2, 4, 24.3217, -110.3242, now(), 'ficha')
$q$, 'P0001')
UNION ALL
SELECT * FROM fn_probar_rechazo('SP-c RN7: fecha en el futuro', $q$
    CALL sp_registrar_avistamiento(3, 2, 1, 24.1665, -110.3121, now() + INTERVAL '1 day', 'ficha')
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('SP-d cámara sin detección', $q$
    CALL sp_registrar_avistamiento(3, 2, 1, 24.1665, -110.3121, now(), 'camara')
$q$, 'P0001')
UNION ALL
SELECT * FROM fn_probar_rechazo('SP-e especie inexistente', $q$
    CALL sp_registrar_avistamiento(3, 999, 1, 24.1665, -110.3121, now(), 'ficha')
$q$, '23503')
UNION ALL
SELECT * FROM fn_probar_rechazo('SP-f detección inválida en el 2.º paso (confianza 1.4)', $q$
    CALL sp_registrar_avistamiento(3, 2, 1, 24.1665, -110.3121, now(), 'camara',
        NULL, false, 2, 1.4, 0.1, 0.1, 0.3, 0.3, 'vuela-v1')
$q$, '23514');

-- Mismo número que antes: ningún avistamiento huérfano.
SELECT count(*) AS avistamientos_despues FROM avistamientos;

-- ---------------------------------------------------------------------
-- B4. trg_validar_revision / sp_revisar_avistamiento — rechazos (P04)
-- ---------------------------------------------------------------------
SELECT * FROM fn_probar_rechazo('P04a un turista intenta revisar', $q$
    CALL sp_revisar_avistamiento(6, 4, 'validado')
$q$, 'P0001')
UNION ALL
SELECT * FROM fn_probar_rechazo('P04b el biólogo revisa su propio avistamiento', $q$
    CALL sp_revisar_avistamiento(19, 1, 'validado')
$q$, 'P0001')
UNION ALL
SELECT * FROM fn_probar_rechazo('P04c revisar un avistamiento ya revisado', $q$
    INSERT INTO revisiones (avistamiento_id, revisor_id, decision) VALUES (1, 2, 'rechazado')
$q$, 'P0001')
UNION ALL
SELECT * FROM fn_probar_rechazo('P04d decisión no permitida', $q$
    CALL sp_revisar_avistamiento(6, 1, 'dudoso')
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('P04e avistamiento inexistente', $q$
    CALL sp_revisar_avistamiento(999, 1, 'validado')
$q$, '23503');

-- ---------------------------------------------------------------------
-- B5. trg_validar_revision + trg_aplicar_revision — casos exitosos
-- ---------------------------------------------------------------------
-- Con el procedimiento: Biólogo 1 valida el #5 (Turista 3 baja a 4 pendientes).
CALL sp_revisar_avistamiento(5, 1, 'validado', 'Coincide con la especie.');

-- Con INSERT directo: Biólogo 2 valida el #19 (registrado por Biólogo 1).
INSERT INTO revisiones (avistamiento_id, revisor_id, decision)
VALUES (19, 2, 'validado');

-- El estado cambió solo por la revisión.
SELECT a.avistamiento_id, a.estado, r.decision, r.revisor_id
FROM avistamientos a JOIN revisiones r USING (avistamiento_id)
WHERE a.avistamiento_id IN (5, 19)
ORDER BY 1;

-- ---------------------------------------------------------------------
-- B6. trg_proteger_estado — rechazos (P04)
-- ---------------------------------------------------------------------
SELECT * FROM fn_probar_rechazo('P04f validar con UPDATE directo, sin revisión', $q$
    UPDATE avistamientos SET estado = 'validado' WHERE avistamiento_id = 6
$q$, 'P0001')
UNION ALL
SELECT * FROM fn_probar_rechazo('P04g regresar a pendiente un validado', $q$
    UPDATE avistamientos SET estado = 'pendiente' WHERE avistamiento_id = 1
$q$, 'P0001')
UNION ALL
SELECT * FROM fn_probar_rechazo('P04h insertar un avistamiento ya validado', $q$
    INSERT INTO avistamientos (usuario_id, especie_id, sitio_id, latitud, longitud, estado)
    VALUES (3, 2, 1, 24.1665, -110.3121, 'validado')
$q$, 'P0001');

-- Caso exitoso: cambiar otra columna (no el estado) sí se permite.
-- Se hace dentro de una transacción que se deshace para no alterar los datos.
BEGIN;
UPDATE avistamientos SET latitud = 24.321000 WHERE avistamiento_id = 6;
SELECT avistamiento_id, latitud, estado FROM avistamientos WHERE avistamiento_id = 6;
ROLLBACK;

-- ---------------------------------------------------------------------
-- B7. trg_contar_avistamiento — DELETE (éxito) y DELETE de revisado (rechazo)
-- ---------------------------------------------------------------------
-- Éxito: Turista 2 borra su avistamiento pendiente #16 → pinzón baja 1 y su
-- detección se borra en cascada.
SELECT total_registros AS pinzon_antes FROM especies WHERE especie_id = 4;
DELETE FROM avistamientos WHERE avistamiento_id = 16;
SELECT total_registros AS pinzon_despues FROM especies WHERE especie_id = 4;
SELECT count(*) AS detecciones_del_16 FROM detecciones WHERE avistamiento_id = 16;

-- Éxito: corregir la especie de un avistamiento mueve los dos contadores
-- (dentro de una transacción que se deshace).
BEGIN;
UPDATE avistamientos SET especie_id = 8 WHERE avistamiento_id = 18;   -- tortolita → paloma
SELECT especie_id, slug, total_registros FROM especies WHERE especie_id IN (8, 10) ORDER BY 1;
ROLLBACK;

-- Rechazo: un avistamiento revisado no se puede borrar; el contador no cambia.
SELECT * FROM fn_probar_rechazo('CONT-a borrar avistamiento revisado #1', $q$
    DELETE FROM avistamientos WHERE avistamiento_id = 1
$q$, '23503');
SELECT total_registros AS cardenal_sin_cambio FROM especies WHERE especie_id = 2;

-- ---------------------------------------------------------------------
-- B8. trg_auditoria
-- ---------------------------------------------------------------------
-- Éxito: eventos generados por las pruebas de arriba (usuario_app_id se llena
-- cuando el cambio vino de un procedimiento; NULL si fue SQL directo).
SELECT bitacora_id, tabla, operacion, registro_id, usuario_db, usuario_app_id, fecha_hora,
       datos_anteriores ->> 'estado' AS estado_antes,
       datos_nuevos     ->> 'estado' AS estado_despues
FROM bitacora_auditoria
ORDER BY bitacora_id;

-- Los cambios del contador (total_registros) no generan eventos de especies.
SELECT count(*) AS eventos_de_especies FROM bitacora_auditoria WHERE tabla = 'especies';

-- Rechazo: una operación fallida no deja evento (se revierte con todo lo demás).
SELECT count(*) AS eventos_antes FROM bitacora_auditoria;
SELECT * FROM fn_probar_rechazo('AUD-a sitio con nombre repetido', $q$
    INSERT INTO sitios (nombre, latitud, longitud) VALUES ('Malecón', 24.1, -110.3)
$q$, '23505');
SELECT count(*) AS eventos_despues FROM bitacora_auditoria;


-- ---------------------------------------------------------------------
-- B9. Inicio de sesión (contraseña de prueba de todos: vuela2026)
-- ---------------------------------------------------------------------
-- Éxito: credenciales correctas, sin importar mayúsculas en el correo → 1 fila.
SELECT 'LOGIN-a correcto' AS prueba, * FROM fn_verificar_credenciales('Turista1@VueLa.test', 'vuela2026');

-- Rechazos: devuelven 0 filas (la app solo dice «correo o contraseña incorrectos»).
SELECT 'LOGIN-b contraseña incorrecta' AS prueba, count(*) AS filas FROM fn_verificar_credenciales('turista1@vuela.test', 'otra-clave')
UNION ALL
SELECT 'LOGIN-c usuario inactivo (Turista 5)', count(*) FROM fn_verificar_credenciales('turista5@vuela.test', 'vuela2026')
UNION ALL
SELECT 'LOGIN-d correo que no existe', count(*) FROM fn_verificar_credenciales('nadie@vuela.test', 'vuela2026');

-- Éxito: registro de una cuenta nueva (queda como turista, id 8).
SELECT fn_registrar_usuario('Turista Nuevo', 'Nuevo@Vuela.test', 'clave-segura-1') AS nuevo_usuario_id;
SELECT u.usuario_id, u.nombre, u.correo, r.nombre AS rol, left(u.contrasena_hash, 7) || '…' AS hash_guardado
FROM usuarios u JOIN roles r ON r.rol_id = u.rol_id
WHERE u.correo = 'nuevo@vuela.test';

-- La bitácora registró el alta, pero sin el hash de la contraseña.
SELECT tabla, operacion, registro_id, datos_nuevos ? 'contrasena_hash' AS bitacora_tiene_hash
FROM bitacora_auditoria
WHERE tabla = 'usuarios' ORDER BY bitacora_id DESC LIMIT 1;

-- Rechazos del registro.
SELECT * FROM fn_probar_rechazo('REG-a correo ya registrado (otras mayúsculas)', $q$
    SELECT fn_registrar_usuario('Otra persona', 'TURISTA1@vuela.test', 'clave-segura-1')
$q$, '23505')
UNION ALL
SELECT * FROM fn_probar_rechazo('REG-b contraseña de menos de 8 caracteres', $q$
    SELECT fn_registrar_usuario('Otra persona', 'otra@vuela.test', 'corta')
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('REG-c correo sin formato válido', $q$
    SELECT fn_registrar_usuario('Otra persona', 'otra-sin-arroba', 'clave-segura-1')
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('REG-d sin nombre', $q$
    SELECT fn_registrar_usuario('  ', 'otra@vuela.test', 'clave-segura-1')
$q$, '23514');


-- =====================================================================
-- PARTE C. EXTRA (RN8): vistas públicas y rol vuela_invitado
-- =====================================================================

-- Catálogo público: oculta clase_yolo y total_registros.
CREATE OR REPLACE VIEW v_catalogo_especies AS
SELECT slug, nombre_comun, nombre_cientifico, estatus, descripcion, habitat, region, foto_url
FROM especies;

-- Mapa público: solo validados y con ubicación real (sin ubicacion_aprox);
-- no muestra correo, autor ni revisor.
CREATE OR REPLACE VIEW v_mapa_publico AS
SELECT a.avistamiento_id,
       e.slug,
       e.nombre_comun,
       e.nombre_cientifico,
       e.estatus,
       s.nombre AS sitio,
       a.latitud,
       a.longitud,
       a.fecha_hora
FROM avistamientos a
JOIN especies e ON e.especie_id = a.especie_id
JOIN sitios   s ON s.sitio_id   = a.sitio_id
WHERE a.estado = 'validado'
  AND NOT a.ubicacion_aprox;

-- El rol pertenece al servidor, no a la base: se crea solo si no existe
-- (así el script corre varias veces y también con vuela_restore).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vuela_invitado') THEN
        CREATE ROLE vuela_invitado NOLOGIN;
    END IF;
    -- Para probar con SET ROLE, quien corre el script debe ser miembro del rol
    -- (un superusuario no lo necesita).
    IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        BEGIN
            EXECUTE format('GRANT vuela_invitado TO %I', current_user);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'No se pudo otorgar vuela_invitado a %: %', current_user, SQLERRM;
        END;
    END IF;
END $$;

REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM vuela_invitado;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM vuela_invitado;
GRANT USAGE  ON SCHEMA public TO vuela_invitado;
GRANT SELECT ON v_catalogo_especies, v_mapa_publico TO vuela_invitado;

-- ---------------------------------------------------------------------
-- P13 · Permisos del invitado
-- ---------------------------------------------------------------------
SET ROLE vuela_invitado;

SELECT current_user AS rol_actual;
SELECT * FROM v_catalogo_especies ORDER BY nombre_comun;
SELECT * FROM v_mapa_publico ORDER BY fecha_hora;   -- solo validados sin ubicación aproximada

SELECT * FROM fn_probar_rechazo('P13a invitado lee la tabla usuarios', $q$
    SELECT * FROM usuarios
$q$, '42501')
UNION ALL
SELECT * FROM fn_probar_rechazo('P13b invitado inserta en avistamientos', $q$
    INSERT INTO avistamientos (usuario_id, especie_id, sitio_id, latitud, longitud)
    VALUES (3, 2, 1, 24.1665, -110.3121)
$q$, '42501')
UNION ALL
SELECT * FROM fn_probar_rechazo('P13c invitado llama al procedimiento de registro', $q$
    CALL sp_registrar_avistamiento(3, 2, 1, 24.1665, -110.3121, now(), 'ficha')
$q$, '42501')
UNION ALL
SELECT * FROM fn_probar_rechazo('P13d invitado lee las sesiones abiertas', $q$
    SELECT * FROM sesiones
$q$, '42501')
UNION ALL
SELECT * FROM fn_probar_rechazo('P13e invitado intenta verificar contraseñas', $q$
    SELECT * FROM fn_verificar_credenciales('turista1@vuela.test', 'vuela2026')
$q$, '42501');

RESET ROLE;
SELECT current_user AS rol_restablecido;
