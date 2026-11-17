-- =====================================================================
-- VueLa · Base de Datos II · UABCS
-- 01_estructura.sql — Dominios, tablas, llaves, CHECK, UNIQUE e índices únicos
-- Basado en: Documento de diseño v2, secciones 3 y 4, más el inicio de sesión
-- (columna contrasena_hash y tabla sesiones; ver db/README.md).
-- Requiere PostgreSQL 13 o superior (gen_random_uuid). Probado en PostgreSQL 16.
-- Ejecutar conectado a vuela_db. Se puede correr varias veces: borra y vuelve a crear todo.
-- =====================================================================

SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 0. Limpieza (permite correr el script desde cero cuantas veces haga falta)
-- ---------------------------------------------------------------------
DROP VIEW  IF EXISTS v_mapa_publico, v_catalogo_especies CASCADE;
DROP TABLE IF EXISTS especies_sombra, sesiones, ts_avistamiento, bitacora_auditoria,
                     revisiones, detecciones, avistamientos,
                     sitios, especies, usuarios, roles CASCADE;
DROP DOMAIN IF EXISTS d_probabilidad, d_correo CASCADE;

RESET client_min_messages;

-- ---------------------------------------------------------------------
-- 0b. pgcrypto: cifrado de contraseñas con bcrypt dentro de PostgreSQL.
--     En Supabase ya viene instalada (esquema «extensions»); en Docker o
--     PostgreSQL local se instala aquí.
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Devuelve el hash bcrypt de una contraseña (mínimo 8 caracteres).
-- Nunca se guarda la contraseña: solo este hash.
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

-- ---------------------------------------------------------------------
-- 1. Dominios
-- ---------------------------------------------------------------------
-- Probabilidad o coordenada normalizada: de 0 a 1 con 3 decimales.
CREATE DOMAIN d_probabilidad AS NUMERIC(4,3)
    CONSTRAINT ck_d_probabilidad_rango CHECK (VALUE BETWEEN 0 AND 1);

-- Correo con formato básico usuario@dominio.ext
CREATE DOMAIN d_correo AS VARCHAR(120)
    CONSTRAINT ck_d_correo_formato
    CHECK (VALUE ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$');

-- ---------------------------------------------------------------------
-- 2. roles — catálogo de los dos perfiles de la aplicación
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    rol_id       SMALLINT GENERATED ALWAYS AS IDENTITY
                 CONSTRAINT pk_roles PRIMARY KEY,
    nombre       VARCHAR(20)  NOT NULL
                 CONSTRAINT uq_roles_nombre UNIQUE
                 CONSTRAINT ck_roles_nombre CHECK (nombre IN ('turista', 'biologo')),
    descripcion  VARCHAR(120)
);

-- ---------------------------------------------------------------------
-- 3. usuarios — personas que usan la aplicación
-- ---------------------------------------------------------------------
CREATE TABLE usuarios (
    usuario_id  INT GENERATED ALWAYS AS IDENTITY
                CONSTRAINT pk_usuarios PRIMARY KEY,
    nombre      VARCHAR(80) NOT NULL,
    correo      d_correo    NOT NULL,
    rol_id      SMALLINT    NOT NULL
                CONSTRAINT fk_usuarios_rol REFERENCES roles (rol_id),
    activo      BOOLEAN     NOT NULL DEFAULT true,
    creado_en   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Hash bcrypt de la contraseña (fn_hash_contrasena). El CHECK impide
    -- guardar una contraseña en texto plano por error.
    contrasena_hash TEXT    NOT NULL
                CONSTRAINT ck_usuarios_contrasena_bcrypt
                CHECK (contrasena_hash ~ '^\$2[abxy]\$[0-9]{2}\$[./A-Za-z0-9]{53}$')
);
-- RN1: Ana@x.com y ana@x.com cuentan como el mismo correo.
CREATE UNIQUE INDEX uq_usuarios_correo ON usuarios (lower(correo));

-- ---------------------------------------------------------------------
-- 3b. sesiones — sesiones abiertas de la app (inicio de sesión)
--     Se guarda el SHA-256 del token, nunca el token: si alguien leyera
--     esta tabla no podría usar las sesiones.
-- ---------------------------------------------------------------------
CREATE TABLE sesiones (
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

-- ---------------------------------------------------------------------
-- 4. especies — catálogo de las 10 aves (especies.json)
-- ---------------------------------------------------------------------
CREATE TABLE especies (
    especie_id         SMALLINT GENERATED ALWAYS AS IDENTITY
                       CONSTRAINT pk_especies PRIMARY KEY,
    slug               VARCHAR(60) NOT NULL
                       CONSTRAINT uq_especies_slug UNIQUE,
    nombre_comun       VARCHAR(80) NOT NULL
                       CONSTRAINT uq_especies_nombre_comun UNIQUE,
    nombre_cientifico  VARCHAR(80) NOT NULL
                       CONSTRAINT uq_especies_nombre_cientifico UNIQUE,
    estatus            VARCHAR(12) NOT NULL
                       CONSTRAINT ck_especies_estatus
                       CHECK (estatus IN ('Nativa', 'Endémica', 'Migratoria', 'Introducida')),
    clase_yolo         SMALLINT
                       CONSTRAINT uq_especies_clase_yolo UNIQUE
                       CONSTRAINT ck_especies_clase_yolo CHECK (clase_yolo >= 0),
    descripcion        TEXT,
    habitat            TEXT,
    region             VARCHAR(60) NOT NULL DEFAULT 'Baja California Sur',
    foto_url           TEXT,
    total_registros    INT NOT NULL DEFAULT 0
                       CONSTRAINT ck_especies_total_registros CHECK (total_registros >= 0)
);

-- ---------------------------------------------------------------------
-- 5. sitios — zonas de observación (incluye «Otro»)
-- ---------------------------------------------------------------------
CREATE TABLE sitios (
    sitio_id     SMALLINT GENERATED ALWAYS AS IDENTITY
                 CONSTRAINT pk_sitios PRIMARY KEY,
    nombre       VARCHAR(80)  NOT NULL
                 CONSTRAINT uq_sitios_nombre UNIQUE,
    latitud      NUMERIC(9,6) NOT NULL
                 CONSTRAINT ck_sitios_latitud  CHECK (latitud  BETWEEN  -90 AND  90),
    longitud     NUMERIC(9,6) NOT NULL
                 CONSTRAINT ck_sitios_longitud CHECK (longitud BETWEEN -180 AND 180),
    descripcion  TEXT
);

-- ---------------------------------------------------------------------
-- 6. avistamientos — tabla central
-- ---------------------------------------------------------------------
CREATE TABLE avistamientos (
    avistamiento_id  INT GENERATED ALWAYS AS IDENTITY
                     CONSTRAINT pk_avistamientos PRIMARY KEY,
    uuid_cliente     UUID NOT NULL DEFAULT gen_random_uuid()
                     CONSTRAINT uq_avistamientos_uuid_cliente UNIQUE,
    usuario_id       INT NOT NULL
                     CONSTRAINT fk_avistamientos_usuario REFERENCES usuarios (usuario_id),
    especie_id       SMALLINT NOT NULL
                     CONSTRAINT fk_avistamientos_especie REFERENCES especies (especie_id),
    sitio_id         SMALLINT NOT NULL
                     CONSTRAINT fk_avistamientos_sitio   REFERENCES sitios (sitio_id),
    fecha_hora       TIMESTAMPTZ NOT NULL DEFAULT now(),   -- hora del dispositivo
    recibido_en      TIMESTAMPTZ NOT NULL DEFAULT now(),   -- hora del servidor
    origen           VARCHAR(10) NOT NULL DEFAULT 'camara'
                     CONSTRAINT ck_avistamientos_origen
                     CHECK (origen IN ('camara', 'ficha', 'manual')),
    latitud          NUMERIC(9,6) NOT NULL
                     CONSTRAINT ck_avistamientos_latitud  CHECK (latitud  BETWEEN  -90 AND  90),
    longitud         NUMERIC(9,6) NOT NULL
                     CONSTRAINT ck_avistamientos_longitud CHECK (longitud BETWEEN -180 AND 180),
    ubicacion_aprox  BOOLEAN NOT NULL DEFAULT false,
    estado           VARCHAR(10) NOT NULL DEFAULT 'pendiente'
                     CONSTRAINT ck_avistamientos_estado
                     CHECK (estado IN ('pendiente', 'validado', 'rechazado')),
    -- RN7: la fecha del dispositivo no puede estar en el futuro (tolerancia de 5 minutos).
    CONSTRAINT ck_avistamientos_fecha_no_futura
        CHECK (fecha_hora <= recibido_en + INTERVAL '5 minutes')
);
-- RN1: mismo usuario + especie + sitio + minuto no se repite.
CREATE UNIQUE INDEX uq_avistamiento_minuto ON avistamientos
    (usuario_id, especie_id, sitio_id, date_trunc('minute', fecha_hora AT TIME ZONE 'UTC'));

-- ---------------------------------------------------------------------
-- 7. detecciones — resultado del modelo YOLO (relación 1 a 0..1)
-- ---------------------------------------------------------------------
CREATE TABLE detecciones (
    deteccion_id         INT GENERATED ALWAYS AS IDENTITY
                         CONSTRAINT pk_detecciones PRIMARY KEY,
    avistamiento_id      INT NOT NULL
                         CONSTRAINT uq_detecciones_avistamiento UNIQUE
                         CONSTRAINT fk_detecciones_avistamiento
                         REFERENCES avistamientos (avistamiento_id) ON DELETE CASCADE,
    especie_predicha_id  SMALLINT NOT NULL
                         CONSTRAINT fk_detecciones_especie_predicha REFERENCES especies (especie_id),
    confianza            d_probabilidad NOT NULL,
    caja_x               d_probabilidad NOT NULL,
    caja_y               d_probabilidad NOT NULL,
    caja_w               d_probabilidad NOT NULL,
    caja_h               d_probabilidad NOT NULL,
    modelo_version       VARCHAR(20) NOT NULL,          -- 'mock' = detector falso de desarrollo
    creado_en            TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- La caja debe quedar dentro del cuadro.
    CONSTRAINT ck_detecciones_caja_horizontal CHECK (caja_x + caja_w <= 1),
    CONSTRAINT ck_detecciones_caja_vertical   CHECK (caja_y + caja_h <= 1)
);

-- ---------------------------------------------------------------------
-- 8. revisiones — decisión de un biólogo (RN3: una por avistamiento)
-- ---------------------------------------------------------------------
CREATE TABLE revisiones (
    revision_id      INT GENERATED ALWAYS AS IDENTITY
                     CONSTRAINT pk_revisiones PRIMARY KEY,
    avistamiento_id  INT NOT NULL
                     CONSTRAINT uq_revisiones_avistamiento UNIQUE
                     -- Sin cascada: un avistamiento revisado no se puede borrar.
                     CONSTRAINT fk_revisiones_avistamiento
                     REFERENCES avistamientos (avistamiento_id) ON DELETE RESTRICT,
    revisor_id       INT NOT NULL
                     CONSTRAINT fk_revisiones_revisor REFERENCES usuarios (usuario_id),
    decision         VARCHAR(10) NOT NULL
                     CONSTRAINT ck_revisiones_decision CHECK (decision IN ('validado', 'rechazado')),
    comentario       VARCHAR(300),
    revisado_en      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 9. bitacora_auditoria — la llenan los triggers (sin llaves foráneas)
-- ---------------------------------------------------------------------
CREATE TABLE bitacora_auditoria (
    bitacora_id       BIGINT GENERATED ALWAYS AS IDENTITY
                      CONSTRAINT pk_bitacora_auditoria PRIMARY KEY,
    tabla             VARCHAR(40) NOT NULL,
    operacion         VARCHAR(6)  NOT NULL
                      CONSTRAINT ck_bitacora_operacion CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
    registro_id       INT,
    usuario_db        TEXT        NOT NULL DEFAULT current_user,
    usuario_app_id    INT,        -- sin FK; viene de vuela.usuario_id (SET LOCAL)
    fecha_hora        TIMESTAMPTZ NOT NULL DEFAULT now(),
    datos_anteriores  JSONB,
    datos_nuevos      JSONB
);

-- ---------------------------------------------------------------------
-- 10. ts_avistamiento — tabla auxiliar del Reto 9 (ordenamiento por marcas de tiempo)
-- ---------------------------------------------------------------------
CREATE TABLE ts_avistamiento (
    avistamiento_id  INT
                     CONSTRAINT pk_ts_avistamiento PRIMARY KEY
                     CONSTRAINT fk_ts_avistamiento_avistamiento
                     REFERENCES avistamientos (avistamiento_id) ON DELETE CASCADE,
    ultima_marca     TIMESTAMPTZ NOT NULL
);

-- ---------------------------------------------------------------------
-- 11. Utilidad para las pruebas de rechazo (P01 a P04, P13)
--     Ejecuta una sentencia que DEBE fallar, deshace cualquier efecto y
--     devuelve una fila con el código SQLSTATE obtenido. Así los scripts
--     corren completos en DBeaver o psql sin detenerse en el primer error.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_probar_rechazo(p_prueba TEXT, p_sql TEXT, p_codigo_esperado TEXT DEFAULT NULL)
RETURNS TABLE (prueba TEXT, resultado TEXT, codigo TEXT, mensaje TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    prueba := p_prueba;
    BEGIN
        EXECUTE p_sql;
        -- Si llegó aquí, la sentencia se aceptó: se fuerza un error para deshacerla.
        RAISE EXCEPTION USING ERRCODE = 'VL000', MESSAGE = 'aceptada';
    EXCEPTION WHEN OTHERS THEN
        codigo  := SQLSTATE;
        mensaje := SQLERRM;
    END;

    IF codigo = 'VL000' THEN
        resultado := 'FALLA: se aceptó (efecto deshecho)';
        codigo := NULL; mensaje := NULL;
    ELSIF p_codigo_esperado IS NULL OR codigo = p_codigo_esperado THEN
        resultado := 'OK: rechazada';
    ELSE
        resultado := 'FALLA: se esperaba ' || p_codigo_esperado;
    END IF;
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION fn_probar_rechazo(TEXT, TEXT, TEXT) IS
    'Auxiliar de pruebas: ejecuta una sentencia que debe fallar y reporta el SQLSTATE.';

-- Verificación rápida: deben aparecer 10 tablas.
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name;
