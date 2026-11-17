-- =====================================================================
-- VueLa · Base de Datos II · UABCS
-- actualizar_catalogo.sql — Carga fotos y textos del catálogo en una base
-- que ya existe, sin borrar avistamientos ni otros datos.
--
-- Lo ejecuta el administrador por SQL (sección 2 del documento de diseño):
-- cada especie modificada deja un evento UPDATE en bitacora_auditoria.
-- Las bases nuevas no lo necesitan: 02_datos.sql ya trae estos valores.
--
-- descripcion y habitat: textos preliminares redactados a partir de
-- Audubon Guide to North American Birds y Wikipedia (fuentes en
-- db/README.md); PENDIENTES DE VALIDAR por el biólogo del proyecto.
-- foto_url: ruta de la foto dentro de la app (assets/aves/<slug>.jpg),
-- tomadas de aves_comunes.pdf.
-- =====================================================================

UPDATE especies e
SET descripcion = t.descripcion,
    habitat     = t.habitat,
    foto_url    = t.foto_url
FROM (VALUES
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
) AS t(slug, descripcion, habitat, foto_url)
WHERE e.slug = t.slug
  AND (e.descripcion, e.habitat, e.foto_url) IS DISTINCT FROM (t.descripcion, t.habitat, t.foto_url);

-- Verificación: las 10 especies con foto y sin el texto de ejemplo.
SELECT slug, foto_url, left(descripcion, 60) AS descripcion, left(habitat, 60) AS habitat
FROM especies
ORDER BY especie_id;
