import Foundation

enum CatalogCategory: String, Codable, CaseIterable, Identifiable {
    case movies = "Películas y series"
    case spanishCinema = "Cine español"
    case live = "Canales en directo"
    case documentaries = "Documentales"
    case courses = "Cursos"
    case talks = "Conferencias"
    case music = "Música"
    case other = "Otros"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .movies: return "film.stack"
        case .spanishCinema: return "theatermasks"
        case .live: return "antenna.radiowaves.left.and.right"
        case .documentaries: return "globe.europe.africa"
        case .courses: return "graduationcap"
        case .talks: return "mic"
        case .music: return "music.quarternote.3"
        case .other: return "link"
        }
    }
}

enum CatalogDuration: String, Codable, CaseIterable, Identifiable {
    case short = "Corto (<30 min)"
    case medium = "Medio (30–90 min)"
    case long = "Largo (>90 min)"
    case mixed = "Variado"
    var id: String { rawValue }
}

struct CatalogEntry: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var categories: [CatalogCategory]
    var languages: [String]
    var duration: CatalogDuration
    var topics: [String]
    var summary: String
    var registration: String
    var limitations: String
    var url: URL
    var isCustom: Bool = false

    var inSpanish: Bool { languages.contains("Castellano") }
}

/// Catálogo de servicios gratuitos y legales, con prioridad para España y el castellano.
/// Revisado en noviembre de 2026: la oferta cambia a menudo, así que conviene comprobar cada servicio.
enum Catalog {
    private static func u(_ s: String) -> URL { URL(string: s)! }

    static let entries: [CatalogEntry] = [
        // Películas y series
        CatalogEntry(id: "rtveplay", name: "RTVE Play",
                     categories: [.movies, .spanishCinema, .documentaries, .live],
                     languages: ["Castellano", "Catalán"], duration: .mixed,
                     topics: ["Cine español", "Series", "Documentales", "TV en directo"],
                     summary: "La plataforma pública de RTVE: cine español (sección Somos Cine), series, documentales y los canales de TVE en directo.",
                     registration: "No para ver; registro gratuito opcional para guardar favoritos.",
                     limitations: "Algunos títulos solo están disponibles una temporada o solo en España.",
                     url: u("https://www.rtve.es/play/")),
        CatalogEntry(id: "efilm", name: "eFilm (bibliotecas públicas)",
                     categories: [.movies, .spanishCinema, .documentaries],
                     languages: ["Castellano", "Versión original"], duration: .mixed,
                     topics: ["Cine de autor", "Estrenos", "Clásicos", "Series"],
                     summary: "Préstamo digital de películas, series y documentales (gran parte del catálogo de Filmin) con tu carné de biblioteca.",
                     registration: "Sí: carné de una biblioteca pública de una comunidad adherida.",
                     limitations: "Número limitado de préstamos según tu biblioteca; no todas las comunidades participan.",
                     url: u("https://efilm.online")),
        CatalogEntry(id: "plutotv", name: "Pluto TV",
                     categories: [.movies, .live],
                     languages: ["Castellano"], duration: .mixed,
                     topics: ["Cine doblado", "Series clásicas", "Canales temáticos 24 h"],
                     summary: "Más de 100 canales temáticos y una sección de películas y series a la carta, doblados al castellano.",
                     registration: "No es obligatorio.",
                     limitations: "Incluye anuncios; el catálogo a la carta rota con frecuencia.",
                     url: u("https://pluto.tv/")),
        CatalogEntry(id: "rakutenfree", name: "Rakuten TV (sección gratis)",
                     categories: [.movies, .live],
                     languages: ["Castellano"], duration: .mixed,
                     topics: ["Películas con anuncios", "Canales FAST"],
                     summary: "Películas gratuitas con anuncios y unos 90 canales lineales gratuitos en España.",
                     registration: "Registro gratuito.",
                     limitations: "No confundir con el videoclub de alquiler o compra, que es de pago.",
                     url: u("https://www.rakuten.tv/es")),
        CatalogEntry(id: "plex", name: "Plex (cine gratis)",
                     categories: [.movies, .live, .documentaries],
                     languages: ["Castellano", "Inglés"], duration: .mixed,
                     topics: ["Películas", "Documentales", "Canales"],
                     summary: "Películas, series y canales gratuitos con anuncios. Cada vez más contenido en español.",
                     registration: "Opcional.",
                     limitations: "Gran parte del catálogo sigue en inglés.",
                     url: u("https://watch.plex.tv")),
        CatalogEntry(id: "atresplayer", name: "Atresplayer (gratis)",
                     categories: [.movies, .live],
                     languages: ["Castellano"], duration: .mixed,
                     topics: ["Series españolas", "TV en directo"],
                     summary: "Directos de los canales de Atresmedia y parte de sus series y programas a la carta.",
                     registration: "Registro gratuito para parte del contenido.",
                     limitations: "Con anuncios; el catálogo completo es de pago.",
                     url: u("https://www.atresplayer.com")),
        CatalogEntry(id: "mediaset", name: "Mediaset Infinity (gratis)",
                     categories: [.movies, .live],
                     languages: ["Castellano"], duration: .mixed,
                     topics: ["Series españolas", "TV en directo"],
                     summary: "Directos y contenido a la carta de los canales de Mediaset España.",
                     registration: "Registro gratuito para algunas funciones.",
                     limitations: "Con anuncios; hay una modalidad de pago con más contenido.",
                     url: u("https://www.mediasetinfinity.es")),
        CatalogEntry(id: "tivify", name: "Tivify",
                     categories: [.live, .movies],
                     languages: ["Castellano"], duration: .mixed,
                     topics: ["TDT por internet", "Cine en diferido"],
                     summary: "Cientos de canales en abierto de España y otros países en una sola app.",
                     registration: "Plan gratuito con registro.",
                     limitations: "Algunas funciones (grabaciones, más calidad) son de pago.",
                     url: u("https://www.tivify.tv")),
        CatalogEntry(id: "platfo", name: "PLATFO (Ministerio de Cultura)",
                     categories: [.spanishCinema, .talks],
                     languages: ["Castellano"], duration: .short,
                     topics: ["Cine clásico y mudo", "Cortometrajes", "Tráilers", "Pódcast"],
                     summary: "Plataforma pública del ICAA: patrimonio del cine español (muchos cortos y cine de los inicios), tráilers y pódcast.",
                     registration: "No.",
                     limitations: "En fase beta: pocas películas largas actuales.",
                     url: u("https://apps.apple.com/es/app/id6757526281")),
        CatalogEntry(id: "archivefilms", name: "Internet Archive · Películas de dominio público",
                     categories: [.movies],
                     languages: ["Inglés", "Varios"], duration: .long,
                     topics: ["Clásicos", "Cine mudo", "Dominio público"],
                     summary: "Miles de películas antiguas en dominio público, descargables y reproducibles en esta app.",
                     registration: "No.",
                     limitations: "Mayoría en inglés; calidad de imagen variable.",
                     url: u("https://archive.org/details/feature_films")),

        // Documentales
        CatalogEntry(id: "rtvedocs", name: "RTVE Play · Documentales",
                     categories: [.documentaries],
                     languages: ["Castellano"], duration: .medium,
                     topics: ["Historia", "Naturaleza", "Ciencia", "Sociedad"],
                     summary: "Documentales de producción propia y adquiridos, incluidos los de La 2.",
                     registration: "No.",
                     limitations: "Disponibilidad temporal según derechos.",
                     url: u("https://www.rtve.es/play/documentales/")),
        CatalogEntry(id: "arte", name: "ARTE en español",
                     categories: [.documentaries],
                     languages: ["Castellano (subtítulos)", "Castellano"], duration: .medium,
                     topics: ["Cultura europea", "Historia", "Geopolítica", "Arte"],
                     summary: "Selección de documentales europeos con subtítulos en español.",
                     registration: "No.",
                     limitations: "Los vídeos caducan tras un tiempo.",
                     url: u("https://www.arte.tv/es/")),

        // Cursos y conferencias
        CatalogEntry(id: "khan", name: "Khan Academy en español",
                     categories: [.courses],
                     languages: ["Castellano"], duration: .short,
                     topics: ["Matemáticas", "Ciencias", "Programación", "Economía"],
                     summary: "Lecciones en vídeo y ejercicios desde primaria hasta universidad.",
                     registration: "Opcional (para guardar tu progreso).",
                     limitations: "Algunas materias solo están en inglés.",
                     url: u("https://es.khanacademy.org")),
        CatalogEntry(id: "uned", name: "CanalUNED",
                     categories: [.courses, .talks, .documentaries],
                     languages: ["Castellano"], duration: .mixed,
                     topics: ["Universidad", "Humanidades", "Ciencia", "Derecho"],
                     summary: "Clases, conferencias, programas de radio y documentales de la UNED.",
                     registration: "No.",
                     limitations: "Interfaz algo anticuada.",
                     url: u("https://canal.uned.es")),
        CatalogEntry(id: "ted", name: "TED en español",
                     categories: [.talks],
                     languages: ["Castellano", "Castellano (subtítulos)"], duration: .short,
                     topics: ["Ciencia", "Tecnología", "Psicología", "Creatividad"],
                     summary: "Charlas breves de expertos, muchas en español o subtituladas.",
                     registration: "No.",
                     limitations: "La mayoría son en inglés con subtítulos.",
                     url: u("https://www.ted.com/talks?language=es")),
        CatalogEntry(id: "aprendemos", name: "Aprendemos juntos (BBVA)",
                     categories: [.talks],
                     languages: ["Castellano"], duration: .medium,
                     topics: ["Educación", "Psicología", "Divulgación"],
                     summary: "Entrevistas y conferencias divulgativas en español.",
                     registration: "No.",
                     limitations: "Contenido patrocinado por una entidad bancaria.",
                     url: u("https://aprendemosjuntos.bbva.com")),
        CatalogEntry(id: "march", name: "Fundación Juan March",
                     categories: [.talks, .music],
                     languages: ["Castellano"], duration: .long,
                     topics: ["Historia", "Arte", "Música clásica", "Literatura"],
                     summary: "Ciclos de conferencias y conciertos grabados, de libre acceso.",
                     registration: "No.",
                     limitations: "Formato largo, pensado para escuchar con calma.",
                     url: u("https://www.march.es")),
        CatalogEntry(id: "coursera", name: "Coursera (modo oyente)",
                     categories: [.courses],
                     languages: ["Castellano", "Inglés"], duration: .long,
                     topics: ["Universidad", "Tecnología", "Negocios"],
                     summary: "Cursos de universidades; muchos permiten ver las clases gratis como oyente.",
                     registration: "Sí, gratuito.",
                     limitations: "El certificado y algunas tareas son de pago.",
                     url: u("https://www.coursera.org")),
        CatalogEntry(id: "mitocw", name: "MIT OpenCourseWare",
                     categories: [.courses],
                     languages: ["Inglés"], duration: .long,
                     topics: ["Ingeniería", "Matemáticas", "Física", "Informática"],
                     summary: "Asignaturas completas del MIT con vídeos y apuntes, con licencia abierta.",
                     registration: "No.",
                     limitations: "En inglés.",
                     url: u("https://ocw.mit.edu")),

        // Música
        CatalogEntry(id: "rtveradio", name: "RNE y Radio 3 (RTVE Play Radio)",
                     categories: [.music, .live],
                     languages: ["Castellano"], duration: .mixed,
                     topics: ["Radio en directo", "Pódcast", "Música española"],
                     summary: "Emisoras de Radio Nacional en directo y miles de programas a la carta.",
                     registration: "No.",
                     limitations: "Ninguna relevante.",
                     url: u("https://www.rtve.es/play/radio/")),
        CatalogEntry(id: "jamendo", name: "Jamendo Music",
                     categories: [.music],
                     languages: ["Varios"], duration: .short,
                     topics: ["Artistas independientes", "Creative Commons"],
                     summary: "Música de artistas independientes con licencias Creative Commons, para escuchar y descargar.",
                     registration: "Opcional (para descargar).",
                     limitations: "Pocos artistas conocidos.",
                     url: u("https://www.jamendo.com")),
        CatalogEntry(id: "fma", name: "Free Music Archive",
                     categories: [.music],
                     languages: ["Varios"], duration: .short,
                     topics: ["Independiente", "Electrónica", "Creative Commons"],
                     summary: "Archivo de música libre y legal para descargar y añadir a tu biblioteca.",
                     registration: "Opcional.",
                     limitations: "Revisa la licencia de cada tema.",
                     url: u("https://freemusicarchive.org")),
        CatalogEntry(id: "musopen", name: "Musopen",
                     categories: [.music],
                     languages: ["Varios"], duration: .mixed,
                     topics: ["Música clásica", "Dominio público"],
                     summary: "Grabaciones de música clásica sin derechos de autor.",
                     registration: "Opcional; algunas descargas requieren cuenta.",
                     limitations: "Límite de descargas diarias sin cuenta.",
                     url: u("https://musopen.org")),
        CatalogEntry(id: "archiveaudio", name: "Internet Archive · Audio",
                     categories: [.music],
                     languages: ["Varios"], duration: .mixed,
                     topics: ["Conciertos en directo", "Discos antiguos", "Audiolibros"],
                     summary: "Conciertos con permiso de grabación, discos de 78 rpm digitalizados y audiolibros libres.",
                     registration: "No.",
                     limitations: "Calidad y licencias variables.",
                     url: u("https://archive.org/details/audio")),
        CatalogEntry(id: "bandcamp", name: "Bandcamp",
                     categories: [.music],
                     languages: ["Varios"], duration: .short,
                     topics: ["Artistas independientes"],
                     summary: "Escucha gratis discos de artistas independientes; compra opcional para apoyarles.",
                     registration: "No para escuchar.",
                     limitations: "Algunos discos limitan las escuchas gratuitas.",
                     url: u("https://bandcamp.com")),
    ]

    static let languages: [String] = ["Castellano", "Catalán", "Inglés", "Varios"]
}
