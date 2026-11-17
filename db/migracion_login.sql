-- =====================================================================
-- VueLa · Base de Datos II · UABCS
-- migracion_login.sql — Agrega el inicio de sesión a una base que ya
-- existe (Supabase o Docker) SIN borrar datos.
--
-- Las bases nuevas no lo necesitan: 01, 02 y 03 ya traen todo esto.
-- Se puede correr más de una vez. Todo va en una transacción: si algo
-- falla, la base queda como estaba.
--
-- Qué hace:
--   1. Instala pgcrypto (en Supabase ya existe) y crea fn_hash_contrasena.
--   2. La bitácora deja de copiar el hash de la contraseña.
--   3. Agrega usuarios.contrasena_hash; a los usuarios que no tengan
--      contraseña les pone la de prueba «vuela2026» (cada quien puede
--      pedir al administrador que se la cambie).
--   4. Crea la tabla sesiones y las funciones de registro y verificación.
--   5. Quita al invitado cualquier permiso sobre la tabla sesiones.
-- =====================================================================

BEGIN;

-- 1. pgcrypto y función de hash -----------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION fn_hash_contrasena(p_contrasena TEXT)
RETURNS TEXT
LANGUAGE plpgsql VOLATILE
SET search_path = public, extensions
AS $$
BEGIN
    IF p_contrasena IS NULL OR length(p_contrasena) < 8 THEN
        RAISE EXCEPTION 'La contraseña debe tener al menos 8 caracteres.'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN crypt(p_contrasena, gen_salt('bf', 10));
END;
$$;

-- 2. Bitácora sin el hash (antes de tocar usuarios) ----------------------
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

-- 3. Columna de la contraseña --------------------------------------------
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS contrasena_hash TEXT;

UPDATE usuarios
SET contrasena_hash = fn_hash_contrasena('vuela2026')
WHERE contrasena_hash IS NULL;

ALTER TABLE usuarios ALTER COLUMN contrasena_hash SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_usuarios_contrasena_bcrypt') THEN
        ALTER TABLE usuarios ADD CONSTRAINT ck_usuarios_contrasena_bcrypt
            CHECK (contrasena_hash ~ '^\$2[abxy]\$[0-9]{2}\$[./A-Za-z0-9]{53}$');
    END IF;
END $$;

-- 4. Sesiones y funciones -------------------------------------------------
CREATE TABLE IF NOT EXISTS sesiones (
    sesion_id   BIGINT GENERATED ALWAYS AS IDENTITY
                CONSTRAINT pk_sesiones PRIMARY KEY,
    token_hash  CHAR(64)    NOT NULL
                CONSTRAINT uq_sesiones_token UNIQUE
                CONSTRAINT ck_sesiones_token CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    usuario_id  INT         NOT NULL
                CONSTRAINT fk_sesiones_usuario REFERENCES usuarios (usuario_id) ON DELETE CASCADE,
    creada_en   TIMESTAMPTZ NOT NULL DEFAULT now(),
    expira_en   TIMESTAMPTZ NOT NULL,
    CONSTRAINT ck_sesiones_vigencia CHECK (expira_en > creada_en)
);

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

-- 5. El invitado no ve las sesiones -------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vuela_invitado') THEN
        REVOKE ALL ON sesiones FROM vuela_invitado;
    END IF;
END $$;

COMMIT;

-- Verificación: todos los usuarios con hash bcrypt y la prueba de login.
SELECT count(*) AS usuarios,
       count(*) FILTER (WHERE contrasena_hash LIKE '$2%') AS con_contrasena_cifrada
FROM usuarios;
SELECT 'login de prueba' AS verificacion, * FROM fn_verificar_credenciales('turista1@vuela.test', 'vuela2026');
