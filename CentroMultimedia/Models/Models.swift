import Foundation

// MARK: - Tipos de contenido

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case movie, episode, music, video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movie: return "Películas"
        case .episode: return "Series"
        case .music: return "Música"
        case .video: return "Vídeos"
        }
    }

    /// Carpeta dentro de "Biblioteca" (nombres compatibles con Jellyfin).
    var folderName: String {
        switch self {
        case .movie: return "Peliculas"
        case .episode: return "Series"
        case .music: return "Musica"
        case .video: return "Videos"
        }
    }

    var systemImage: String {
        switch self {
        case .movie: return "film"
        case .episode: return "tv"
        case .music: return "music.note"
        case .video: return "video"
        }
    }
}

enum MediaTypes {
    static let video: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg", "ts", "m2ts", "3gp"]
    static let audio: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "alac", "ogg", "opus", "wma", "caf"]
    static let subtitles: Set<String> = ["srt", "vtt"]
    /// Formatos que el reproductor nativo de iOS abre sin conversión.
    static let nativeVideo: Set<String> = ["mp4", "m4v", "mov", "3gp"]
    static let nativeAudio: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "caf", "alac"]
}

// MARK: - Elemento de la biblioteca

struct MediaItem: Codable, Identifiable, Hashable {
    var id: String
    var relativePath: String
    var kind: MediaKind
    var title: String
    var year: Int?
    var show: String?
    var season: Int?
    var episode: Int?
    var artist: String?
    var album: String?
    var duration: Double?
    var artworkFile: String?
    var overview: String?
    var genre: String?
    var hash: String?
    var fileSize: Int64
    var addedAt: Date
    var isFavorite: Bool
    var metadataChecked: Bool

    init(id: String = UUID().uuidString, relativePath: String, kind: MediaKind, title: String,
         fileSize: Int64, hash: String?) {
        self.id = id
        self.relativePath = relativePath
        self.kind = kind
        self.title = title
        self.fileSize = fileSize
        self.hash = hash
        self.addedAt = Date()
        self.isFavorite = false
        self.metadataChecked = false
    }

    var url: URL { FileLocations.documents.appendingPathComponent(relativePath) }
    var fileExtension: String { (relativePath as NSString).pathExtension.lowercased() }
    var artworkURL: URL? { artworkFile.map { FileLocations.artwork.appendingPathComponent($0) } }

    var isNativelyPlayable: Bool {
        kind == .music ? MediaTypes.nativeAudio.contains(fileExtension) : MediaTypes.nativeVideo.contains(fileExtension)
    }

    var displayTitle: String {
        if kind == .episode, let s = season, let e = episode {
            return String(format: "T%d · E%02d", s, e)
        }
        return title
    }

    var subtitleLine: String {
        switch kind {
        case .movie: return [year.map(String.init), genre].compactMap { $0 }.joined(separator: " · ")
        case .episode: return show ?? ""
        case .music: return [artist, album].compactMap { $0 }.joined(separator: " · ")
        case .video: return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }
    }
}

struct Playlist: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var itemIDs: [String] = []
}

struct PlaybackProgress: Codable, Hashable {
    var position: Double
    var duration: Double
    var updated: Date
    var fraction: Double { duration > 0 ? min(1, position / duration) : 0 }
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var itemID: String
    var title: String
    var subtitle: String
    var date: Date
}

// MARK: - Organizador

struct MoveRecord: Codable, Hashable {
    var from: String
    var to: String
}

struct OrganizeBatch: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var moves: [MoveRecord]
}

struct ScanReport: Codable {
    var date: Date
    var added: Int
    var duplicates: Int
    var moved: Int
    var missing: Int
    var errors: [String]

    var summary: String {
        var parts = ["\(added) nuevos", "\(moved) ordenados", "\(duplicates) duplicados apartados"]
        if missing > 0 { parts.append("\(missing) ya no están") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Podcasts

struct PodcastEpisode: Codable, Identifiable, Hashable {
    var id: String { url.absoluteString }
    var title: String
    var url: URL
    var date: Date?
    var duration: String?
}

struct PodcastFeed: Codable, Identifiable, Hashable {
    var id: String { feedURL.absoluteString }
    var title: String
    var feedURL: URL
    var artworkURL: URL?
    var episodes: [PodcastEpisode]
    var updated: Date
}

// MARK: - Estado persistido

struct PersistedState: Codable {
    var items: [MediaItem] = []
    var playlists: [Playlist] = []
    var progress: [String: PlaybackProgress] = [:]
    var history: [HistoryEntry] = []
    var favoriteCatalogIDs: Set<String> = []
    var customEntries: [CatalogEntry] = []
    var podcasts: [PodcastFeed] = []
    var batches: [OrganizeBatch] = []
    var pinnedPaths: Set<String> = []
    var lastReport: ScanReport?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([MediaItem].self, forKey: .items)) ?? []
        playlists = (try? c.decodeIfPresent([Playlist].self, forKey: .playlists)) ?? []
        progress = (try? c.decodeIfPresent([String: PlaybackProgress].self, forKey: .progress)) ?? [:]
        history = (try? c.decodeIfPresent([HistoryEntry].self, forKey: .history)) ?? []
        favoriteCatalogIDs = (try? c.decodeIfPresent(Set<String>.self, forKey: .favoriteCatalogIDs)) ?? []
        customEntries = (try? c.decodeIfPresent([CatalogEntry].self, forKey: .customEntries)) ?? []
        podcasts = (try? c.decodeIfPresent([PodcastFeed].self, forKey: .podcasts)) ?? []
        batches = (try? c.decodeIfPresent([OrganizeBatch].self, forKey: .batches)) ?? []
        pinnedPaths = (try? c.decodeIfPresent(Set<String>.self, forKey: .pinnedPaths)) ?? []
        lastReport = try? c.decodeIfPresent(ScanReport.self, forKey: .lastReport)
    }
}

// MARK: - Rutas

enum FileLocations {
    static var fm: FileManager { FileManager.default }

    static var documents: URL { fm.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var inbox: URL { documents.appendingPathComponent("Entrada", isDirectory: true) }
    static var library: URL { documents.appendingPathComponent("Biblioteca", isDirectory: true) }
    static var duplicates: URL { library.appendingPathComponent("Duplicados", isDirectory: true) }

    static var support: URL {
        let u = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CentroMultimedia", isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static var artwork: URL {
        let u = support.appendingPathComponent("Caratulas", isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func ensureFolders() {
        var folders = [inbox, duplicates]
        folders += MediaKind.allCases.map { library.appendingPathComponent($0.folderName, isDirectory: true) }
        for f in folders { try? fm.createDirectory(at: f, withIntermediateDirectories: true) }
    }

    static func relativePath(of url: URL) -> String {
        let base = documents.resolvingSymlinksInPath().standardizedFileURL.path
        let p = url.resolvingSymlinksInPath().standardizedFileURL.path
        if p.hasPrefix(base + "/") { return String(p.dropFirst(base.count + 1)) }
        return url.lastPathComponent
    }
}
