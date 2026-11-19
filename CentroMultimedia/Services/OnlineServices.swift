import Foundation
import Security

// MARK: - Metadatos y carátulas (API pública de búsqueda de Apple, gratuita y sin clave)

struct ITunesResult: Decodable {
    let trackName: String?
    let collectionName: String?
    let artistName: String?
    let artworkUrl100: String?
    let artworkUrl600: String?
    let releaseDate: String?
    let longDescription: String?
    let shortDescription: String?
    let description: String?
    let primaryGenreName: String?
    let feedUrl: String?
}

private struct ITunesResponse: Decodable { let results: [ITunesResult] }

enum MetadataService {
    /// Busca en la tienda española para obtener títulos y sinopsis en castellano.
    static func search(_ term: String, media: String, entity: String, limit: Int = 5) async throws -> [ITunesResult] {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: media),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "country", value: "ES"),
            URLQueryItem(name: "lang", value: "es_es"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        return try JSONDecoder().decode(ITunesResponse.self, from: data).results
    }

    struct Found {
        var overview: String?
        var genre: String?
        var year: Int?
        var artworkURL: URL?
    }

    static func lookup(_ item: MediaItem) async -> Found? {
        do {
            switch item.kind {
            case .movie:
                let r = try await search(item.title, media: "movie", entity: "movie")
                let best = r.first { res in
                    guard let y = item.year else { return true }
                    return res.releaseDate?.hasPrefix(String(y)) == true
                } ?? r.first
                guard let b = best else { return nil }
                return Found(overview: b.longDescription ?? b.shortDescription, genre: b.primaryGenreName,
                             year: b.releaseDate.flatMap { Int($0.prefix(4)) }, artworkURL: bigArtwork(b.artworkUrl100))
            case .episode:
                let r = try await search(item.show ?? item.title, media: "tvShow", entity: "tvSeason")
                guard let b = r.first else { return nil }
                return Found(overview: b.longDescription ?? b.description, genre: b.primaryGenreName,
                             year: nil, artworkURL: bigArtwork(b.artworkUrl100))
            case .music:
                let term = [item.artist, item.album ?? item.title].compactMap { $0 }.joined(separator: " ")
                let r = try await search(term, media: "music", entity: "album")
                guard let b = r.first else { return nil }
                return Found(overview: nil, genre: b.primaryGenreName, year: nil, artworkURL: bigArtwork(b.artworkUrl100))
            case .video:
                return nil
            }
        } catch {
            return nil
        }
    }

    static func bigArtwork(_ s: String?) -> URL? {
        guard let s else { return nil }
        return URL(string: s.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
    }

    static func download(_ url: URL) async -> Data? {
        try? await URLSession.shared.data(from: url).0
    }
}

// MARK: - Subtítulos (.srt / .vtt)

struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

enum SubtitleParser {
    static func parse(data: Data) -> [SubtitleCue] {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1) ?? ""
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let idx = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[idx].components(separatedBy: "-->")
            guard parts.count == 2, let s = time(parts[0]), let e = time(parts[1]) else { continue }
            let body = lines[(idx + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\{\\[^}]*\}"#, with: "", options: .regularExpression)
            if !body.isEmpty { cues.append(SubtitleCue(start: s, end: e, text: body)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    static func time(_ s: String) -> Double? {
        let token = s.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        let comps = token.replacingOccurrences(of: ",", with: ".").split(separator: ":").map(String.init)
        guard comps.count >= 2 else { return nil }
        var secs = 0.0
        for c in comps {
            guard let v = Double(c) else { return nil }
            secs = secs * 60 + v
        }
        return secs
    }
}

// MARK: - Podcasts (RSS)

final class RSSParser: NSObject, XMLParserDelegate {
    var channelTitle = ""
    var image: URL?
    var episodes: [PodcastEpisode] = []

    private var inItem = false
    private var text = ""
    private var curTitle = ""
    private var curURL: URL?
    private var curDate: Date?
    private var curDuration: String?

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    static func parse(_ data: Data) -> RSSParser {
        let p = RSSParser()
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        return p
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "item":
            inItem = true
            curTitle = ""; curURL = nil; curDate = nil; curDuration = nil
        case "enclosure":
            if inItem, let u = attributeDict["url"] { curURL = URL(string: u) }
        case "itunes:image":
            if !inItem, image == nil, let h = attributeDict["href"] { image = URL(string: h) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title":
            if inItem { curTitle = t } else if channelTitle.isEmpty { channelTitle = t }
        case "pubDate":
            if inItem { curDate = Self.dateFormatter.date(from: t) }
        case "itunes:duration":
            if inItem { curDuration = t }
        case "item":
            inItem = false
            if let u = curURL { episodes.append(PodcastEpisode(title: curTitle, url: u, date: curDate, duration: curDuration)) }
        default: break
        }
        text = ""
    }
}

enum PodcastService {
    static func fetch(_ feedURL: URL) async throws -> PodcastFeed {
        let (data, _) = try await URLSession.shared.data(from: feedURL)
        let p = RSSParser.parse(data)
        return PodcastFeed(title: p.channelTitle.isEmpty ? feedURL.host ?? "Podcast" : p.channelTitle,
                           feedURL: feedURL, artworkURL: p.image, episodes: p.episodes, updated: Date())
    }

    static func search(_ term: String) async throws -> [ITunesResult] {
        try await MetadataService.search(term, media: "podcast", entity: "podcast", limit: 20)
    }
}

// MARK: - Llavero (para la sesión de Jellyfin)

enum Keychain {
    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "CentroMultimedia",
         kSecAttrAccount as String: key]
    }

    static func set(_ data: Data, for key: String) {
        SecItemDelete(base(key) as CFDictionary)
        var add = base(key)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> Data? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
    }
}
