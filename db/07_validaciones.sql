-- =====================================================================
-- VueLa · Base de Datos II · UABCS
-- 07_validaciones.sql — Consultas de calidad (Reto 1.4) y verificaciones
-- posteriores a cada prueba.
-- Basado en: Documento de diseño v2, sección 7 (consultas de calidad) y P08.
--
-- Solo lee: se puede correr cuantas veces haga falta (después de 03, después
-- de 04, después de las sesiones 05/06 y en vuela_restore).
-- =====================================================================

SET timezone = 'America/Mazatlan';

-- ---------------------------------------------------------------------
-- 1. RESUMEN DE CALIDAD
--    «anomalias» debe ser 0 en las verificaciones con esperado = 0.
--    Las del grupo 4 son informativas (calidad del origen del dato).
-- ---------------------------------------------------------------------
SELECT grupo, verificacion, anomalias, esperado,
       CASE WHEN esperado = 'informativo' THEN 'INFO'
            WHEN anomalias = 0 THEN 'OK' ELSE 'REVISAR' END AS estado
FROM (
    -- (1) Duplicados
    SELECT 1 AS orden, '1 duplicados' AS grupo,
           'correos que difieren solo en mayúsculas' AS verificacion,
           (SELECT count(*) FROM (SELECT lower(correo) FROM usuarios
                                  GROUP BY lower(correo) HAVING count(*) > 1) d) AS anomalias,
           '0' AS esperado
    UNION ALL
    SELECT 2, '1 duplicados', 'avistamientos casi iguales (usuario, especie, sitio y minuto)',
           (SELECT count(*) FROM (SELECT 1 FROM avistamientos
                                  GROUP BY usuario_id, especie_id, sitio_id,
                                           date_trunc('minute', fecha_hora AT TIME ZONE 'UTC')
                                  HAVING count(*) > 1) d), '0'
    -- (2) Valores faltantes
    UNION ALL
    SELECT 3, '2 faltantes', 'avistamientos de cámara sin detección',
           (SELECT count(*) FROM avistamientos a
            WHERE a.origen = 'camara'
              AND NOT EXISTS (SELECT 1 FROM detecciones d WHERE d.avistamiento_id = a.avistamiento_id)), '0'
    UNION ALL
    SELECT 4, '2 faltantes', 'detecciones en avistamientos que no son de cámara',
           (SELECT count(*) FROM detecciones d JOIN avistamientos a USING (avistamiento_id)
            WHERE a.origen <> 'camara'), '0'
    UNION ALL
    SELECT 5, '2 faltantes', 'usuarios sin rol o sin correo',
           (SELECT count(*) FROM usuarios u
            WHERE u.correo IS NULL OR u.correo = ''
               OR NOT EXISTS (SELECT 1 FROM roles r WHERE r.rol_id = u.rol_id)), '0'
    -- (3) Inconsistencias de negocio
    UNION ALL
    SELECT 6, '3 inconsistencias', 'total_registros distinto del conteo real (RN5)',
           (SELECT count(*) FROM especies e
            WHERE e.total_registros <> (SELECT count(*) FROM avistamientos a
                                        WHERE a.especie_id = e.especie_id)), '0'
    UNION ALL
    SELECT 7, '3 inconsistencias', 'estado del avistamiento distinto de la decisión de su revisión',
           (SELECT count(*) FROM avistamientos a JOIN revisiones r USING (avistamiento_id)
            WHERE a.estado <> r.decision), '0'
    UNION ALL
    SELECT 8, '3 inconsistencias', 'avistamientos no pendientes sin revisión',
           (SELECT count(*) FROM avistamientos a
            WHERE a.estado <> 'pendiente'
              AND NOT EXISTS (SELECT 1 FROM revisiones r WHERE r.avistamiento_id = a.avistamiento_id)), '0'
    UNION ALL
    SELECT 9, '3 inconsistencias', 'revisiones hechas por alguien que no es biólogo',
           (SELECT count(*) FROM revisiones r
            JOIN usuarios u ON u.usuario_id = r.revisor_id
            JOIN roles ro   ON ro.rol_id    = u.rol_id
            WHERE ro.nombre <> 'biologo'), '0'
    UNION ALL
    SELECT 10, '3 inconsistencias', 'revisiones del propio autor',
           (SELECT count(*) FROM revisiones r JOIN avistamientos a USING (avistamiento_id)
            WHERE r.revisor_id = a.usuario_id), '0'
    UNION ALL
    SELECT 11, '3 inconsistencias', 'turistas con más de 5 pendientes (RN6)',
           (SELECT count(*) FROM (SELECT a.usuario_id FROM avistamientos a
                                  JOIN usuarios u USING (usuario_id)
                                  JOIN roles r ON r.rol_id = u.rol_id
                                  WHERE a.estado = 'pendiente' AND r.nombre = 'turista'
                                  GROUP BY a.usuario_id HAVING count(*) > 5) d), '0'
    -- (4) Calidad del origen del dato (informativo)
    UNION ALL
    SELECT 12, '4 origen del dato', 'detecciones del detector falso (modelo_version = mock)',
           (SELECT count(*) FROM detecciones WHERE modelo_version = 'mock'), 'informativo'
    UNION ALL
    SELECT 13, '4 origen del dato', 'avistamientos con ubicación aproximada (sin GPS)',
           (SELECT count(*) FROM avistamientos WHERE ubicacion_aprox), 'informativo'
) v
ORDER BY orden;

-- ---------------------------------------------------------------------
-- 2. DETALLE (cada consulta debe salir vacía, salvo las del grupo 4)
-- ---------------------------------------------------------------------
-- (1a) Correos repetidos sin distinguir mayúsculas
SELECT lower(correo) AS correo, count(*) AS veces
FROM usuarios GROUP BY lower(correo) HAVING count(*) > 1;

-- (1b) Avistamientos casi iguales
SELECT usuario_id, especie_id, sitio_id,
       date_trunc('minute', fecha_hora) AS minuto, count(*) AS veces
FROM avistamientos
GROUP BY usuario_id, especie_id, sitio_id, date_trunc('minute', fecha_hora AT TIME ZONE 'UTC'),
         date_trunc('minute', fecha_hora)
HAVING count(*) > 1;

-- (2a) Avistamientos de cámara sin detección
SELECT a.avistamiento_id, a.usuario_id, a.fecha_hora
FROM avistamientos a
WHERE a.origen = 'camara'
  AND NOT EXISTS (SELECT 1 FROM detecciones d WHERE d.avistamiento_id = a.avistamiento_id);

-- (2b) Usuarios sin rol o sin correo
SELECT u.usuario_id, u.nombre
FROM usuarios u
WHERE u.correo IS NULL OR u.correo = ''
   OR NOT EXISTS (SELECT 1 FROM roles r WHERE r.rol_id = u.rol_id);

-- (3a) Contador distinto del conteo real
SELECT e.especie_id, e.slug, e.total_registros, count(a.avistamiento_id) AS conteo_real
FROM especies e LEFT JOIN avistamientos a ON a.especie_id = e.especie_id
GROUP BY e.especie_id
HAVING e.total_registros <> count(a.avistamiento_id);

-- (3b) Estado distinto de la decisión
SELECT a.avistamiento_id, a.estado, r.decision
FROM avistamientos a JOIN revisiones r USING (avistamiento_id)
WHERE a.estado <> r.decision;

-- (3c) No pendientes sin revisión
SELECT a.avistamiento_id, a.estado
FROM avistamientos a
WHERE a.estado <> 'pendiente'
  AND NOT EXISTS (SELECT 1 FROM revisiones r WHERE r.avistamiento_id = a.avistamiento_id);

-- (3d) Revisiones hechas por alguien que no es biólogo
SELECT r.revision_id, r.revisor_id, ro.nombre AS rol
FROM revisiones r
JOIN usuarios u ON u.usuario_id = r.revisor_id
JOIN roles ro   ON ro.rol_id    = u.rol_id
WHERE ro.nombre <> 'biologo';

-- (4a) Detecciones del detector falso
SELECT d.deteccion_id, d.avistamiento_id, d.confianza, d.modelo_version
FROM detecciones d WHERE d.modelo_version = 'mock' ORDER BY d.deteccion_id;

-- (4b) Avistamientos con ubicación aproximada (no salen en el mapa público)
SELECT a.avistamiento_id, a.origen, a.latitud, a.longitud, a.estado
FROM avistamientos a WHERE a.ubicacion_aprox ORDER BY a.avistamiento_id;

-- (4c) Calidad del modelo sin el detector falso: confianza promedio y
--      cuántas veces el usuario corrigió la especie predicha.
SELECT d.modelo_version,
       count(*)                                         AS detecciones,
       round(avg(d.confianza), 3)                       AS confianza_promedio,
       count(*) FILTER (WHERE d.especie_predicha_id <> a.especie_id) AS corregidas_por_usuario
FROM detecciones d JOIN avistamientos a USING (avistamiento_id)
WHERE d.modelo_version <> 'mock'
GROUP BY d.modelo_version;

-- ---------------------------------------------------------------------
-- 3. OPERACIONES CLAVE (sección 2 de la propuesta)
-- ---------------------------------------------------------------------
-- Contar registros por especie (contador vs. conteo por estado)
SELECT e.nombre_comun, e.total_registros,
       count(a.*) FILTER (WHERE a.estado = 'validado')  AS validados,
       count(a.*) FILTER (WHERE a.estado = 'pendiente') AS pendientes,
       count(a.*) FILTER (WHERE a.estado = 'rechazado') AS rechazados
FROM especies e LEFT JOIN avistamientos a ON a.especie_id = e.especie_id
GROUP BY e.especie_id
ORDER BY e.total_registros DESC, e.nombre_comun;

-- Historial de un usuario (ejemplo: Turista 1)
SELECT a.avistamiento_id, a.fecha_hora, e.nombre_comun, s.nombre AS sitio, a.origen, a.estado,
       d.confianza, d.modelo_version
FROM avistamientos a
JOIN usuarios u ON u.usuario_id = a.usuario_id
JOIN especies e ON e.especie_id = a.especie_id
JOIN sitios   s ON s.sitio_id   = a.sitio_id
LEFT JOIN detecciones d ON d.avistamiento_id = a.avistamiento_id
WHERE lower(u.correo) = 'turista1@vuela.test'
ORDER BY a.fecha_hora DESC;

-- Pendientes para revisar (lo que vería un biólogo; excluye los suyos)
SELECT a.avistamiento_id, a.fecha_hora, e.nombre_comun, s.nombre AS sitio,
       u.nombre AS autor, d.confianza
FROM avistamientos a
JOIN usuarios u ON u.usuario_id = a.usuario_id
JOIN especies e ON e.especie_id = a.especie_id
JOIN sitios   s ON s.sitio_id   = a.sitio_id
LEFT JOIN detecciones d ON d.avistamiento_id = a.avistamiento_id
WHERE a.estado = 'pendiente'
  AND a.usuario_id <> (SELECT usuario_id FROM usuarios WHERE lower(correo) = 'biologo1@vuela.test')
ORDER BY a.fecha_hora;

-- Mapa público
SELECT * FROM v_mapa_publico ORDER BY fecha_hora;

-- Bitácora de cambios (últimos 20)
SELECT bitacora_id, fecha_hora, tabla, operacion, registro_id, usuario_db, usuario_app_id
FROM bitacora_auditoria
ORDER BY bitacora_id DESC
LIMIT 20;

-- ---------------------------------------------------------------------
-- 4. P08 · VERIFICACIÓN DE RESTAURACIÓN
--    Correr esta sección en vuela_db y en vuela_restore: ambas salidas
--    deben ser idénticas (conteos por tabla y huella de los contadores).
-- ---------------------------------------------------------------------
SELECT tabla, registros FROM (
              SELECT 1 AS o, 'roles' AS tabla, count(*) AS registros FROM roles
    UNION ALL SELECT 2, 'usuarios',           count(*) FROM usuarios
    UNION ALL SELECT 3, 'especies',           count(*) FROM especies
    UNION ALL SELECT 4, 'sitios',             count(*) FROM sitios
    UNION ALL SELECT 5, 'avistamientos',      count(*) FROM avistamientos
    UNION ALL SELECT 6, 'detecciones',        count(*) FROM detecciones
    UNION ALL SELECT 7, 'revisiones',         count(*) FROM revisiones
    UNION ALL SELECT 8, 'bitacora_auditoria', count(*) FROM bitacora_auditoria
    UNION ALL SELECT 9, 'ts_avistamiento',    count(*) FROM ts_avistamiento
    UNION ALL SELECT 10, 'sesiones',          count(*) FROM sesiones
) t ORDER BY o;

SELECT slug, total_registros FROM especies ORDER BY slug;

SELECT md5(string_agg(slug || ':' || total_registros, ',' ORDER BY slug)) AS huella_contadores,
       sum(total_registros) AS suma_contadores
FROM especies;
