-- =====================================================================
-- VueLa · Base de Datos II · UABCS
-- 02_datos.sql — Datos de prueba (61 registros) y recálculo de contadores
-- Basado en: Documento de diseño v2, sección 7.
--
-- Orden de carga: se ejecuta DESPUÉS de 01 y ANTES de 03 (como lo haría el
-- administrador por SQL). Los estados y contadores se cargan ya consistentes;
-- los eventos de la bitácora se generan después, en las pruebas de 03 y 04.
--
--   roles 2 · usuarios 7 · especies 10 · sitios 6 · avistamientos 15
--   detecciones 13 · revisiones 8  →  total 61
-- =====================================================================

-- Fechas en hora de La Paz, B.C.S. (solo afecta cómo se muestran).
SET timezone = 'America/Mazatlan';

-- ---------------------------------------------------------------------
-- 0. Protección: si los triggers ya existen, los datos de abajo serían
--    rechazados (avistamientos ya revisados). En ese caso, correr 01 de nuevo.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
               WHERE c.relname = 'avistamientos' AND NOT t.tgisinternal) THEN
        RAISE EXCEPTION 'Los triggers de 03 ya existen. Corre 01_estructura.sql y luego 02_datos.sql.';
    END IF;
END $$;

TRUNCATE sesiones, ts_avistamiento, bitacora_auditoria, revisiones, detecciones, avistamientos,
         sitios, especies, usuarios, roles RESTART IDENTITY CASCADE;

-- ---------------------------------------------------------------------
-- 1. roles (2)
-- ---------------------------------------------------------------------
INSERT INTO roles (nombre, descripcion) VALUES
    ('turista', 'Registra avistamientos, ve catálogo, mapa e historial propio.'),
    ('biologo', 'Todo lo del turista, más validar o rechazar avistamientos pendientes.');

-- ---------------------------------------------------------------------
-- 2. usuarios (7): 2 biólogos y 5 turistas (uno inactivo).
--    Nombres y correos genéricos de prueba (dominio .test, no existen).
--    El primero es el «primer biólogo», creado por el administrador con SQL.
--    Contraseña de prueba de todos: vuela2026 (se guarda solo su hash bcrypt).
-- ---------------------------------------------------------------------
INSERT INTO usuarios (nombre, correo, rol_id, activo, contrasena_hash)
SELECT v.nombre, v.correo, r.rol_id, v.activo, fn_hash_contrasena('vuela2026')
FROM (VALUES
    (1, 'Biólogo 1', 'biologo1@vuela.test', 'biologo', true),
    (2, 'Biólogo 2', 'biologo2@vuela.test', 'biologo', true),
    (3, 'Turista 1', 'turista1@vuela.test', 'turista', true),
    (4, 'Turista 2', 'turista2@vuela.test', 'turista', true),
    (5, 'Turista 3', 'turista3@vuela.test', 'turista', true),
    (6, 'Turista 4', 'turista4@vuela.test', 'turista', true),
    (7, 'Turista 5', 'turista5@vuela.test', 'turista', false)   -- inactivo, para probar reglas
) AS v(n, nombre, correo, rol, activo)
JOIN roles r ON r.nombre = v.rol
ORDER BY v.n;

-- ---------------------------------------------------------------------
-- 3. especies (10): datos de data/especies.json.
--    clase_yolo = posición (desde 0) del slug en models/labels.json.
--    descripcion y habitat: textos preliminares redactados a partir de
--    Audubon Guide to North American Birds y Wikipedia (fuentes en
--    db/README.md); PENDIENTES DE VALIDAR por el biólogo del proyecto.
--    foto_url: ruta de la foto dentro de la app (fotos de aves_comunes.pdf).
-- ---------------------------------------------------------------------
INSERT INTO especies (slug, nombre_comun, nombre_cientifico, estatus, clase_yolo, descripcion, habitat, foto_url)
SELECT v.slug, v.nombre, v.cientifico, v.estatus, v.clase, t.descripcion, t.habitat, t.foto_url
FROM (VALUES
    ( 1, 'calandria-dorso-negro-menor', 'Calandria Dorso Negro Menor', 'Icterus cucullatus',             'Nativa',   6),
    ( 2, 'cardenal-rojo',               'Cardenal Rojo',               'Cardinalis cardinalis',          'Nativa',   2),
    ( 3, 'carpintero-del-desierto',     'Carpintero del Desierto',     'Melanerpes uropygialis',         'Nativa',   7),
    ( 4, 'pinzon-mexicano',             'Pinzón Mexicano',             'Haemorhous mexicanus',           'Nativa',   5),
    ( 5, 'matraca-del-desierto',        'Matraca del Desierto',        'Campylorhynchus brunneicapillus','Nativa',   0),
    ( 6, 'caracara-o-quelele',          'Caracara o Quelele',          'Caracara plancus cheriway',      'Nativa',   1),
    ( 7, 'zopilote-aura',               'Zopilote Aura',               'Cathartes aura',                 'Nativa',   3),
    ( 8, 'paloma-alas-blancas',         'Paloma Alas Blancas',         'Zenaida asiatica',               'Nativa',   9),
    ( 9, 'cuicacoche-bajacaliforniano', 'Cuicacoche Bajacaliforniano', 'Toxostoma cinereum',             'Endémica', 8),
    (10, 'tortolita-pico-rojo',         'Tortolita Pico Rojo',         'Columbina passerina',            'Nativa',   4)
) AS v(n, slug, nombre, cientifico, estatus, clase)
JOIN (VALUES
 ('calandria-dorso-negro-menor',
  'Mide de 18 a 20 cm. El macho tiene la cabeza y las partes inferiores amarillo-anaranjadas, con un antifaz negro que llega a la garganta, y la espalda, las alas y la cola negras con dos barras blancas en el ala. La hembra es verde oliva por encima y amarillenta por debajo. El pico es delgado y ligeramente curvo.',
  'Áreas abiertas con árboles, sobre todo palmeras; también arboledas junto a arroyos, parques y jardines de las ciudades. Cuelga su nido tejido bajo las hojas de palmas o yucas y se alimenta de insectos y del néctar de las flores. Es residente todo el año en Baja California.',
  'assets/aves/calandria-dorso-negro-menor.jpg'),
 ('cardenal-rojo',
  'Mide de 21 a 23 cm. El macho es rojo carmesí con una máscara negra que va de los ojos a la parte superior del pecho; la hembra es pardo grisácea con tonos rojizos en las alas, la cresta y la cola. Ambos sexos tienen una cresta prominente y un pico grueso y cónico de color coral.',
  'Matorrales altos, arroyos secos, vegetación junto a los cauces y bosquetes de mezquite; también jardines y zonas urbanas. Es residente todo el año: no migra.',
  'assets/aves/cardenal-rojo.jpg'),
 ('carpintero-del-desierto',
  'Mide de 20 a 25 cm. La espalda, las alas y la cola tienen barras blancas y negras, y la cabeza y las partes inferiores son color pardo claro. El macho tiene una pequeña mancha roja en la coronilla. En vuelo muestra un parche blanco en el ala.',
  'Zonas desérticas con cactus gigantes, arroyos y arboledas de mezquite, sauce o palma; también pueblos y ciudades. Anida en cavidades que excava en cactus gigantes o en árboles grandes. Es residente todo el año.',
  'assets/aves/carpintero-del-desierto.jpg'),
 ('pinzon-mexicano',
  'Ave pequeña de unos 12 cm, de pico grueso. El macho es pardo con el vientre rayado y tiene la frente, una franja sobre el ojo, el pecho y la rabadilla de color rojo, que puede variar hasta anaranjado. La hembra es pardo grisácea, con rayas en el pecho y el vientre.',
  'Muy adaptable: vive en matorrales, desiertos, costas, campos de cultivo y ciudades. En México habita la península de Baja California, los estados del norte y el Altiplano Central. Es mayormente residente.',
  'assets/aves/pinzon-mexicano.jpg'),
 ('matraca-del-desierto',
  'Mide de 18 a 19 cm. Su plumaje es pardo con manchas blancas y negras, con una ceja blanca muy marcada que va del pico a la nuca y el pecho blanco con motas oscuras. Las alas y la cola tienen barras blancas y negras, y el pico es grueso y algo curvo. Machos y hembras son iguales.',
  'Regiones áridas y semidesérticas con cactus (sobre todo choya), yucas y mezquites. Construye un nido voluminoso en forma de bola, con un túnel de entrada, protegido entre las espinas de los cactus. Busca alimento en el suelo y es residente todo el año; en el sur de Baja California vive la subespecie affinis.',
  'assets/aves/matraca-del-desierto.jpg'),
 ('caracara-o-quelele',
  'Ave de presa de 49 a 58 cm y cerca de 1.2 m de envergadura. Tiene la cara de color amarillo-anaranjado, una cresta negra, el cuello y las mejillas blancos y el vientre negro. En vuelo muestra cuatro zonas claras: el pecho, la base de la cola y una mancha cerca de la punta de cada ala. Los jóvenes son más pardos.',
  'Áreas semiabiertas con terreno despejado para cazar y vegetación densa para anidar: desiertos, pastizales, matorrales y costas. Es oportunista: caza animales pequeños, come carroña, escarba en busca de insectos y recorre las carreteras temprano para buscar animales atropellados. Los adultos permanecen todo el año en su territorio.',
  'assets/aves/caracara-o-quelele.jpg'),
 ('zopilote-aura',
  'Ave grande de 64 a 81 cm y cerca de 1.8 m de envergadura, casi toda negra. El adulto tiene la cabeza roja y desnuda; el joven, gris. Por debajo, las alas son de dos tonos: negras al frente y grises en las plumas de vuelo. Planea con las alas levantadas en forma de V abierta.',
  'Campo abierto, desiertos, zonas boscosas y laderas, sobre todo terrenos abiertos cerca de rocas o árboles donde puede anidar; evita el bosque denso. Se alimenta principalmente de carroña, que localiza por el olfato, algo poco común entre las aves.',
  'assets/aves/zopilote-aura.jpg'),
 ('paloma-alas-blancas',
  'Paloma robusta de 28 a 32 cm, de cola corta. Su plumaje es café grisáceo, con un gran parche blanco en el ala muy visible en vuelo y puntas blancas en las plumas externas de la cola. Machos y hembras son iguales.',
  'Matorrales, mezquitales, zonas con cactus gigantes, arboledas, campos de cultivo y poblados. Come semillas, frutos de cactus y néctar de flores grandes; al alimentarse de las flores de los cactus gigantes ayuda a polinizarlos. Las poblaciones del norte migran al sur en otoño.',
  'assets/aves/paloma-alas-blancas.jpg'),
 ('cuicacoche-bajacaliforniano',
  'Mide unos 25 cm. El dorso es pardo grisáceo y el vientre blanco con manchas negras triangulares, más concentradas en el pecho. Las plumas exteriores de la cola tienen puntas blancas.',
  'Matorral desértico. Es endémico de la península de Baja California: se distribuye desde el extremo sur de la península hasta cerca de los 31° N en la costa del Pacífico y de los 29° N en la del golfo de California.',
  'assets/aves/cuicacoche-bajacaliforniano.jpg'),
 ('tortolita-pico-rojo',
  'Paloma pequeña de 15 a 18 cm, con la cola corta y negra de esquinas claras. Tiene un patrón escamado en la cabeza y el pecho y la base del pico rosada. En vuelo, las alas muestran un color rojizo muy vivo.',
  'Zonas semiabiertas con matorral bajo y pastos: huertos, orillas de caminos, ranchos y matorrales de mezquite junto a los arroyos. Es residente en la mayor parte de su área de distribución.',
  'assets/aves/tortolita-pico-rojo.jpg')
) AS t(slug, descripcion, habitat, foto_url) ON t.slug = v.slug
ORDER BY v.n;

-- ---------------------------------------------------------------------
-- 4. sitios (6). Coordenadas aproximadas tomadas de fuentes públicas
--    (ver README.md); conviene validarlas con el biólogo del proyecto.
--    «Otro» usa el CENTRO de La Paz que ya usa la app (js/models/models.js).
-- ---------------------------------------------------------------------
INSERT INTO sitios (nombre, latitud, longitud, descripcion) VALUES
    ('Malecón',              24.166499, -110.312176, 'Malecón de La Paz. Coordenadas aproximadas por validar.'),
    ('Estero El Mogote',     24.163000, -110.362000, 'Península y manglar de El Mogote. Coordenadas aproximadas por validar.'),
    ('Cerro de la Calavera', 24.186960, -110.299070, 'Mirador al norte del centro de La Paz. Coordenadas aproximadas por validar.'),
    ('Playa Balandra',       24.321733, -110.324203, 'Playa y área natural protegida. Coordenadas aproximadas por validar.'),
    ('Playa El Tesoro',      24.254563, -110.314923, 'Playa camino a Pichilingue. Coordenadas aproximadas por validar.'),
    ('Otro',                 24.142600, -110.312800, 'Ubicaciones fuera de las zonas registradas. Coordenadas = centro de La Paz usado por la app.');

-- ---------------------------------------------------------------------
-- 5. avistamientos (15): mezcla de estados y orígenes, varios usuarios.
--    13 de cámara, 1 de ficha y 1 manual. 8 revisados (6 validados,
--    2 rechazados) y 7 pendientes. Dos con ubicacion_aprox = true (sin GPS):
--    el #9 (validado, así se ve que el mapa público lo oculta) y el #12 (ficha).
--    Ningún turista supera 5 pendientes (RN6).
--    recibido_en = fecha_hora + retraso de sincronización (el #14 llegó
--    2 horas después: sincronización tardía sin conexión).
-- ---------------------------------------------------------------------
INSERT INTO avistamientos (uuid_cliente, usuario_id, especie_id, sitio_id, fecha_hora, recibido_en,
                           origen, latitud, longitud, ubicacion_aprox, estado)
SELECT v.uuid::uuid, u.usuario_id, e.especie_id, s.sitio_id,
       v.fecha::timestamptz, v.fecha::timestamptz + v.retraso::interval,
       v.origen, v.lat, v.lng, v.aprox, v.estado
FROM (VALUES
 ( 1,'a0000000-0000-4000-8000-000000000001','turista1@vuela.test','cardenal-rojo',              'Malecón',             '2026-10-03 07:15:20-07','20 seconds','camara',24.166812,-110.311905,false,'validado'),
 ( 2,'a0000000-0000-4000-8000-000000000002','turista1@vuela.test','calandria-dorso-negro-menor','Malecón',             '2026-10-03 07:42:05-07','15 seconds','camara',24.165930,-110.312640,false,'validado'),
 ( 3,'a0000000-0000-4000-8000-000000000003','turista2@vuela.test','zopilote-aura',              'Cerro de la Calavera','2026-10-05 08:10:45-07','30 seconds','camara',24.187210,-110.298840,false,'validado'),
 ( 4,'a0000000-0000-4000-8000-000000000004','turista2@vuela.test','carpintero-del-desierto',    'Cerro de la Calavera','2026-10-05 08:31:10-07','25 seconds','camara',24.186500,-110.299600,false,'rechazado'),
 ( 5,'a0000000-0000-4000-8000-000000000005','turista3@vuela.test','cuicacoche-bajacaliforniano','Playa Balandra',      '2026-10-10 09:02:30-07','40 seconds','camara',24.322010,-110.323650,false,'pendiente'),
 ( 6,'a0000000-0000-4000-8000-000000000006','turista3@vuela.test','caracara-o-quelele',         'Playa Balandra',      '2026-10-10 09:25:00-07','35 seconds','camara',24.320900,-110.324800,false,'pendiente'),
 ( 7,'a0000000-0000-4000-8000-000000000007','turista4@vuela.test','paloma-alas-blancas',        'Playa El Tesoro',     '2026-10-12 17:40:15-07','20 seconds','camara',24.254900,-110.315200,false,'validado'),
 ( 8,'a0000000-0000-4000-8000-000000000008','biologo2@vuela.test','matraca-del-desierto',       'Estero El Mogote',    '2026-10-15 07:05:50-07','10 seconds','camara',24.162400,-110.361300,false,'validado'),
 ( 9,'a0000000-0000-4000-8000-000000000009','turista1@vuela.test','pinzon-mexicano',            'Otro',                '2026-10-18 18:12:00-07','20 seconds','camara',24.146100,-110.308900,true ,'validado'),
 (10,'a0000000-0000-4000-8000-000000000010','turista2@vuela.test','tortolita-pico-rojo',        'Malecón',             '2026-10-22 08:20:40-07','15 seconds','camara',24.167200,-110.311300,false,'rechazado'),
 (11,'a0000000-0000-4000-8000-000000000011','turista3@vuela.test','cardenal-rojo',              'Estero El Mogote',    '2026-11-01 07:30:10-07','30 seconds','camara',24.163600,-110.362700,false,'pendiente'),
 (12,'a0000000-0000-4000-8000-000000000012','turista4@vuela.test','zopilote-aura',              'Otro',                '2026-11-02 12:00:00-07','10 seconds','ficha', 24.139800,-110.316200,true ,'pendiente'),
 (13,'a0000000-0000-4000-8000-000000000013','turista1@vuela.test','matraca-del-desierto',       'Cerro de la Calavera','2026-11-03 08:45:00-07','10 seconds','manual',24.187400,-110.299900,false,'pendiente'),
 (14,'a0000000-0000-4000-8000-000000000014','turista2@vuela.test','caracara-o-quelele',         'Playa Balandra',      '2026-11-04 10:15:30-07','2 hours',   'camara',24.321500,-110.324900,false,'pendiente'),
 (15,'a0000000-0000-4000-8000-000000000015','turista4@vuela.test','carpintero-del-desierto',    'Playa El Tesoro',     '2026-11-05 16:50:20-07','25 seconds','camara',24.254200,-110.314500,false,'pendiente')
) AS v(n, uuid, correo, slug, sitio, fecha, retraso, origen, lat, lng, aprox, estado)
JOIN usuarios u ON lower(u.correo) = v.correo
JOIN especies e ON e.slug = v.slug
JOIN sitios   s ON s.nombre = v.sitio
ORDER BY v.n;

-- ---------------------------------------------------------------------
-- 6. detecciones (13): una por cada avistamiento de cámara.
--    - En el #7 la especie predicha (tortolita) difiere de la registrada
--      (paloma): el usuario corrigió al modelo.
--    - #1, #2 y #15 vienen del detector falso (modelo_version = 'mock';
--      caja fija 0.28/0.30/0.44/0.40 como en js/services/detector/mockDetector.js).
--    - 'vuela-v1' es una versión PROVISIONAL del modelo real: reemplazarla
--      cuando quien entrena YOLO defina la versión.
-- ---------------------------------------------------------------------
INSERT INTO detecciones (avistamiento_id, especie_predicha_id, confianza,
                         caja_x, caja_y, caja_w, caja_h, modelo_version, creado_en)
SELECT a.avistamiento_id, e.especie_id, v.conf, v.x, v.y, v.w, v.h, v.version, a.fecha_hora
FROM (VALUES
 ('a0000000-0000-4000-8000-000000000001','cardenal-rojo',              0.912,0.28,0.30,0.44,0.40,'mock'),
 ('a0000000-0000-4000-8000-000000000002','calandria-dorso-negro-menor',0.874,0.28,0.30,0.44,0.40,'mock'),
 ('a0000000-0000-4000-8000-000000000003','zopilote-aura',              0.958,0.12,0.08,0.70,0.62,'vuela-v1'),
 ('a0000000-0000-4000-8000-000000000004','carpintero-del-desierto',    0.541,0.40,0.35,0.22,0.30,'vuela-v1'),
 ('a0000000-0000-4000-8000-000000000005','cuicacoche-bajacaliforniano',0.887,0.25,0.20,0.45,0.55,'vuela-v1'),
 ('a0000000-0000-4000-8000-000000000006','caracara-o-quelele',         0.903,0.18,0.15,0.60,0.70,'vuela-v1'),
 ('a0000000-0000-4000-8000-000000000007','tortolita-pico-rojo',        0.612,0.33,0.41,0.28,0.26,'vuela-v1'),
 ('a0000000-0000-4000-8000-000000000008','matraca-del-desierto',       0.934,0.30,0.22,0.38,0.50,'vuela-v1'),
 ('a0000000-0000-4000-8000-000000000009','pinzon-mexicano',            0.866,0.36,0.30,0.30,0.34,'vuela-v1'),
 ('a0000000-0000-4000-8000-000000000010','tortolita-pico-rojo',        0.508,0.05,0.60,0.20,0.25,'vuela-v1'),
 ('a0000000-0000-4000-8000-000000000011','cardenal-rojo',              0.921,0.29,0.18,0.40,0.52,'vuela-v1'),
 ('a0000000-0000-4000-8000-000000000014','caracara-o-quelele',         0.779,0.10,0.12,0.55,0.66,'vuela-v1'),
 ('a0000000-0000-4000-8000-000000000015','carpintero-del-desierto',    0.838,0.28,0.30,0.44,0.40,'mock')
) AS v(uuid, slug, conf, x, y, w, h, version)
JOIN avistamientos a ON a.uuid_cliente = v.uuid::uuid
JOIN especies e      ON e.slug = v.slug
ORDER BY a.avistamiento_id;

-- ---------------------------------------------------------------------
-- 7. revisiones (8): validaciones y rechazos de los dos biólogos.
--    Nadie revisa su propio avistamiento (el #8 es del Biólogo 2 y lo revisa
--    el Biólogo 1). La decisión coincide con el estado cargado arriba.
-- ---------------------------------------------------------------------
INSERT INTO revisiones (avistamiento_id, revisor_id, decision, comentario, revisado_en)
SELECT a.avistamiento_id, u.usuario_id, v.decision, v.comentario, v.fecha::timestamptz
FROM (VALUES
 ('a0000000-0000-4000-8000-000000000001','biologo1@vuela.test','validado', NULL,                                                   '2026-10-04 10:00:00-07'),
 ('a0000000-0000-4000-8000-000000000002','biologo1@vuela.test','validado', NULL,                                                   '2026-10-04 10:05:00-07'),
 ('a0000000-0000-4000-8000-000000000003','biologo2@vuela.test','validado', NULL,                                                   '2026-10-06 09:00:00-07'),
 ('a0000000-0000-4000-8000-000000000004','biologo2@vuela.test','rechazado','La foto no permite confirmar la especie.',              '2026-10-06 09:10:00-07'),
 ('a0000000-0000-4000-8000-000000000007','biologo1@vuela.test','validado', 'Especie correcta; el modelo había sugerido otra.',      '2026-10-13 11:20:00-07'),
 ('a0000000-0000-4000-8000-000000000008','biologo1@vuela.test','validado', NULL,                                                   '2026-10-16 09:30:00-07'),
 ('a0000000-0000-4000-8000-000000000009','biologo2@vuela.test','validado', 'Ubicación aproximada: la app no tuvo GPS.',             '2026-10-19 08:45:00-07'),
 ('a0000000-0000-4000-8000-000000000010','biologo2@vuela.test','rechazado','La imagen no corresponde a la especie indicada.',       '2026-10-23 10:15:00-07')
) AS v(uuid, correo, decision, comentario, fecha)
JOIN avistamientos a ON a.uuid_cliente = v.uuid::uuid
JOIN usuarios u      ON lower(u.correo) = v.correo
ORDER BY a.avistamiento_id;

-- ---------------------------------------------------------------------
-- 8. Recálculo de contadores (RN5): total_registros = COUNT real,
--    sin importar el estado del avistamiento.
-- ---------------------------------------------------------------------
UPDATE especies e
SET total_registros = (SELECT count(*) FROM avistamientos a WHERE a.especie_id = e.especie_id);

-- ---------------------------------------------------------------------
-- 9. Verificación de la carga: debe sumar 61.
-- ---------------------------------------------------------------------
SELECT tabla, registros FROM (
    SELECT 1 AS o, 'roles' AS tabla, count(*) AS registros FROM roles
    UNION ALL SELECT 2, 'usuarios',      count(*) FROM usuarios
    UNION ALL SELECT 3, 'especies',      count(*) FROM especies
    UNION ALL SELECT 4, 'sitios',        count(*) FROM sitios
    UNION ALL SELECT 5, 'avistamientos', count(*) FROM avistamientos
    UNION ALL SELECT 6, 'detecciones',   count(*) FROM detecciones
    UNION ALL SELECT 7, 'revisiones',    count(*) FROM revisiones
    UNION ALL SELECT 8, 'TOTAL', (SELECT count(*) FROM roles) + (SELECT count(*) FROM usuarios)
        + (SELECT count(*) FROM especies) + (SELECT count(*) FROM sitios)
        + (SELECT count(*) FROM avistamientos) + (SELECT count(*) FROM detecciones)
        + (SELECT count(*) FROM revisiones)
) t ORDER BY o;

-- =====================================================================
-- 10. Pruebas de restricciones (P01 a P03). Cada fila debe decir
--     «OK: rechazada» con el código esperado. Ninguna deja cambios.
-- =====================================================================

-- P01 · Duplicado único (23505)
SELECT * FROM fn_probar_rechazo('P01a avistamiento repetido en el mismo minuto', $q$
    INSERT INTO avistamientos (usuario_id, especie_id, sitio_id, fecha_hora, recibido_en, latitud, longitud)
    SELECT usuario_id, especie_id, sitio_id, fecha_hora + INTERVAL '30 seconds', recibido_en, latitud, longitud
    FROM avistamientos WHERE uuid_cliente = 'a0000000-0000-4000-8000-000000000001'
$q$, '23505')
UNION ALL
SELECT * FROM fn_probar_rechazo('P01b correo repetido con otras mayúsculas', $q$
    INSERT INTO usuarios (nombre, correo, rol_id, contrasena_hash)
    VALUES ('Copia', 'Turista1@VueLa.TEST', (SELECT rol_id FROM roles WHERE nombre = 'turista'),
            fn_hash_contrasena('vuela2026'))
$q$, '23505')
UNION ALL
SELECT * FROM fn_probar_rechazo('P01c nombre común de especie repetido', $q$
    INSERT INTO especies (slug, nombre_comun, nombre_cientifico, estatus)
    VALUES ('cardenal-2', 'Cardenal Rojo', 'Cardinalis sp.', 'Nativa')
$q$, '23505')
UNION ALL
SELECT * FROM fn_probar_rechazo('P01d uuid_cliente repetido (sincronización doble)', $q$
    INSERT INTO avistamientos (uuid_cliente, usuario_id, especie_id, sitio_id, latitud, longitud)
    VALUES ('a0000000-0000-4000-8000-000000000001', 3, 4, 1, 24.1665, -110.3121)
$q$, '23505');

-- P02 · Valor fuera de dominio (23514)
SELECT * FROM fn_probar_rechazo('P02a confianza 1.4', $q$
    INSERT INTO detecciones (avistamiento_id, especie_predicha_id, confianza, caja_x, caja_y, caja_w, caja_h, modelo_version)
    VALUES ((SELECT avistamiento_id FROM avistamientos WHERE uuid_cliente = 'a0000000-0000-4000-8000-000000000013'),
            1, 1.4, 0.1, 0.1, 0.3, 0.3, 'vuela-v1')
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('P02b caja que sale del cuadro (x + w > 1)', $q$
    INSERT INTO detecciones (avistamiento_id, especie_predicha_id, confianza, caja_x, caja_y, caja_w, caja_h, modelo_version)
    VALUES ((SELECT avistamiento_id FROM avistamientos WHERE uuid_cliente = 'a0000000-0000-4000-8000-000000000013'),
            1, 0.9, 0.7, 0.1, 0.5, 0.3, 'vuela-v1')
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('P02c estado «dudoso»', $q$
    INSERT INTO avistamientos (usuario_id, especie_id, sitio_id, latitud, longitud, estado)
    VALUES (3, 4, 1, 24.1665, -110.3121, 'dudoso')
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('P02d fecha en el futuro (RN7)', $q$
    INSERT INTO avistamientos (usuario_id, especie_id, sitio_id, latitud, longitud, fecha_hora)
    VALUES (3, 4, 1, 24.1665, -110.3121, now() + INTERVAL '1 day')
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('P02e origen «cámara» con acento (la app debe normalizar)', $q$
    INSERT INTO avistamientos (usuario_id, especie_id, sitio_id, latitud, longitud, origen)
    VALUES (3, 4, 1, 24.1665, -110.3121, 'cámara')
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('P02f latitud fuera de rango', $q$
    INSERT INTO avistamientos (usuario_id, especie_id, sitio_id, latitud, longitud)
    VALUES (3, 4, 1, 124.1665, -110.3121)
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('P02g correo sin formato válido', $q$
    INSERT INTO usuarios (nombre, correo, rol_id, contrasena_hash)
    VALUES ('Sin correo', 'sin-arroba.test', (SELECT rol_id FROM roles WHERE nombre = 'turista'),
            fn_hash_contrasena('vuela2026'))
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('P02h contraseña guardada en texto plano', $q$
    INSERT INTO usuarios (nombre, correo, rol_id, contrasena_hash)
    VALUES ('Texto plano', 'plano@vuela.test', (SELECT rol_id FROM roles WHERE nombre = 'turista'), 'vuela2026')
$q$, '23514')
UNION ALL
SELECT * FROM fn_probar_rechazo('P02i contraseña de menos de 8 caracteres', $q$
    INSERT INTO usuarios (nombre, correo, rol_id, contrasena_hash)
    VALUES ('Corta', 'corta@vuela.test', (SELECT rol_id FROM roles WHERE nombre = 'turista'), fn_hash_contrasena('abc'))
$q$, '23514');

-- P03 · Referencia inexistente (23503)
SELECT * FROM fn_probar_rechazo('P03a avistamiento con especie_id 999', $q$
    INSERT INTO avistamientos (usuario_id, especie_id, sitio_id, latitud, longitud)
    VALUES (3, 999, 1, 24.1665, -110.3121)
$q$, '23503')
UNION ALL
SELECT * FROM fn_probar_rechazo('P03b detección con especie_predicha_id inexistente', $q$
    INSERT INTO detecciones (avistamiento_id, especie_predicha_id, confianza, caja_x, caja_y, caja_w, caja_h, modelo_version)
    VALUES ((SELECT avistamiento_id FROM avistamientos WHERE uuid_cliente = 'a0000000-0000-4000-8000-000000000013'),
            999, 0.9, 0.1, 0.1, 0.3, 0.3, 'vuela-v1')
$q$, '23503')
UNION ALL
SELECT * FROM fn_probar_rechazo('P03c usuario con rol inexistente', $q$
    INSERT INTO usuarios (nombre, correo, rol_id, contrasena_hash)
    VALUES ('Sin rol', 'sinrol@vuela.test', 99, fn_hash_contrasena('vuela2026'))
$q$, '23503')
UNION ALL
SELECT * FROM fn_probar_rechazo('P03d borrar un avistamiento ya revisado', $q$
    DELETE FROM avistamientos WHERE uuid_cliente = 'a0000000-0000-4000-8000-000000000001'
$q$, '23503');

-- ---------------------------------------------------------------------
-- 11. Resincronizar las secuencias IDENTITY.
--     Los INSERT rechazados de arriba consumen valores de la secuencia
--     (PostgreSQL no los devuelve al hacer rollback; los huecos son normales).
--     Se resincronizan solo para que los id de las pruebas de 03 sean
--     predecibles (16, 17, 18, 19...).
-- ---------------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('roles',         'rol_id'),          (SELECT max(rol_id)          FROM roles));
SELECT setval(pg_get_serial_sequence('usuarios',      'usuario_id'),      (SELECT max(usuario_id)      FROM usuarios));
SELECT setval(pg_get_serial_sequence('especies',      'especie_id'),      (SELECT max(especie_id)      FROM especies));
SELECT setval(pg_get_serial_sequence('sitios',        'sitio_id'),        (SELECT max(sitio_id)        FROM sitios));
SELECT setval(pg_get_serial_sequence('avistamientos', 'avistamiento_id'), (SELECT max(avistamiento_id) FROM avistamientos));
SELECT setval(pg_get_serial_sequence('detecciones',   'deteccion_id'),    (SELECT max(deteccion_id)    FROM detecciones));
SELECT setval(pg_get_serial_sequence('revisiones',    'revision_id'),     (SELECT max(revision_id)     FROM revisiones));
