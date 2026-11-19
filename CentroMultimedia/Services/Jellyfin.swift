import Foundation
import UIKit

// MARK: - Modelos de la API de Jellyfin

struct JFUserData: Decodable, Hashable {
    let playbackPositionTicks: Int64?
    let played: Bool?
    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks", played = "Played"
    }
}

struct JFStream: Decodable, Hashable {
    let type: String?
    let language: String?
    let index: Int?
    let codec: String?
    let displayTitle: String?
    enum CodingKeys: String, CodingKey {
        case type = "Type", language = "Language", index = "Index", codec = "Codec", displayTitle = "DisplayTitle"
    }
}

struct JFItem: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String?
    let year: Int?
    let overview: String?
    let seriesName: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let collectionType: String?
    let runTimeTicks: Int64?
    let isFolder: Bool?
    let userData: JFUserData?
    let albumArtist: String?
    let mediaStreams: [JFStream]?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", type = "Type", year = "ProductionYear", overview = "Overview"
        case seriesName = "SeriesName", indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber"
        case collectionType = "CollectionType", runTimeTicks = "RunTimeTicks", isFolder = "IsFolder"
        case userData = "UserData", albumArtist = "AlbumArtist", mediaStreams = "MediaStreams"
    }

    static let videoTypes: Set<String> = ["Movie", "Episode", "Video", "MusicVideo", "Trailer"]

    var isVideo: Bool { JFItem.videoTypes.contains(type ?? "") }
    var isAudio: Bool { type == "Audio" }
    var isPlayable: Bool { isVideo || isAudio }

    var subtitleLine: String {
        switch type {
        case "Episode":
            let se = [parentIndexNumber.map { "T\($0)" }, indexNumber.map { "E\($0)" }].compactMap { $0 }.joined(separator: " · ")
            return [seriesName, se].compactMap { $0 }.joined(separator: " — ")
        case "Audio", "MusicAlbum": return albumArtist ?? ""
        default: return year.map(String.init) ?? ""
        }
    }

    var resumeSeconds: Double? {
        guard let t = userData?.playbackPositionTicks, t > 0 else { return nil }
        return Double(t) / 10_000_000
    }
}

private struct JFItemsResponse: Decodable {
    let items: [JFItem]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct JFUser: Decodable {
    let id: String
    let name: String
    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" }
}

private struct JFAuthResponse: Decodable {
    let accessToken: String
    let user: JFUser
    enum CodingKeys: String, CodingKey { case accessToken = "AccessToken", user = "User" }
}

struct JFSession: Codable {
    var server: String
    var userId: String
    var userName: String
    var token: String
}

// MARK: - Cliente

@MainActor
final class JellyfinStore: ObservableObject {
    @Published private(set) var session: JFSession?
    @Published var views: [JFItem] = []
    @Published var resume: [JFItem] = []
    @Published var latest: [JFItem] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let keychainKey = "jellyfin.session"
    private let deviceId: String

    init() {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "deviceId") {
            deviceId = id
        } else {
            let id = UUID().uuidString
            d.set(id, forKey: "deviceId")
            deviceId = id
        }
        if let data = Keychain.get(keychainKey), let s = try? JSONDecoder().decode(JFSession.self, from: data) {
            session = s
        }
    }

    var isLoggedIn: Bool { session != nil }

    private func authHeader(token: String?) -> String {
        var h = "MediaBrowser Client=\"Centro Multimedia\", Device=\"\(UIDevice.current.model)\", DeviceId=\"\(deviceId)\", Version=\"1.0\""
        if let token { h += ", Token=\"\(token)\"" }
        return h
    }

    static func normalize(_ server: String) -> String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        return s
    }

    func login(server: String, user: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let base = Self.normalize(server)
        guard let url = URL(string: base + "/Users/AuthenticateByName") else {
            errorMessage = "La dirección del servidor no es válida."
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader(token: nil), forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["Username": user, "Pw": password])
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                errorMessage = "Usuario o contraseña incorrectos."
                return
            }
            let auth = try JSONDecoder().decode(JFAuthResponse.self, from: data)
            let s = JFSession(server: base, userId: auth.user.id, userName: auth.user.name, token: auth.accessToken)
            if let d = try? JSONEncoder().encode(s) { Keychain.set(d, for: keychainKey) }
            session = s
            await loadHome()
        } catch {
            errorMessage = "No se pudo conectar con el servidor. Comprueba la dirección (p. ej. http://192.168.1.20:8096) y que estás en la misma red."
        }
    }

    func logout() {
        Keychain.delete(keychainKey)
        session = nil
        views = []; resume = []; latest = []
    }

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = []) async throws -> T {
        guard let s = session, var c = URLComponents(string: s.server + path) else { throw URLError(.badURL) }
        if !query.isEmpty { c.queryItems = query }
        guard let url = c.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(authHeader(token: s.token), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            logout()
            throw URLError(.userAuthenticationRequired)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private var fields: URLQueryItem { URLQueryItem(name: "Fields", value: "Overview,PrimaryImageAspectRatio") }

    func loadHome() async {
        guard let s = session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let v: JFItemsResponse = try await get("/Users/\(s.userId)/Views")
            views = v.items
            let r: JFItemsResponse = try await get("/Users/\(s.userId)/Items/Resume",
                                                    [URLQueryItem(name: "Limit", value: "12"),
                                                     URLQueryItem(name: "MediaTypes", value: "Video"), fields])
            resume = r.items
            let l: [JFItem] = try await get("/Users/\(s.userId)/Items/Latest",
                                            [URLQueryItem(name: "Limit", value: "16"), fields])
            latest = l
            errorMessage = nil
        } catch {
            if session != nil { errorMessage = "No se pudo cargar el servidor: \(error.localizedDescription)" }
        }
    }

    func children(of parent: JFItem) async -> [JFItem] {
        guard let s = session else { return [] }
        var q = [URLQueryItem(name: "ParentId", value: parent.id), fields,
                 URLQueryItem(name: "SortBy", value: "SortName")]
        if parent.collectionType == "movies" || parent.collectionType == "tvshows" {
            q.append(URLQueryItem(name: "IncludeItemTypes", value: parent.collectionType == "movies" ? "Movie" : "Series"))
            q.append(URLQueryItem(name: "Recursive", value: "true"))
        }
        if parent.type == "Season" || parent.type == "MusicAlbum" {
            q[2] = URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName")
        }
        let r: JFItemsResponse? = try? await get("/Users/\(s.userId)/Items", q)
        return r?.items ?? []
    }

    func search(_ term: String) async -> [JFItem] {
        guard let s = session, !term.isEmpty else { return [] }
        let r: JFItemsResponse? = try? await get("/Users/\(s.userId)/Items", [
            URLQueryItem(name: "searchTerm", value: term),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series,Episode,Audio,MusicAlbum,Video"),
            URLQueryItem(name: "Limit", value: "60"), fields,
        ])
        return r?.items ?? []
    }

    func details(_ id: String) async -> JFItem? {
        guard let s = session else { return nil }
        return try? await get("/Users/\(s.userId)/Items/\(id)", [URLQueryItem(name: "Fields", value: "MediaStreams,Overview")])
    }

    func imageURL(_ id: String, height: Int = 450) -> URL? {
        guard let s = session else { return nil }
        return URL(string: "\(s.server)/Items/\(id)/Images/Primary?maxHeight=\(height)&quality=85")
    }

    /// Vídeo por HLS (Jellyfin convierte MKV/AVI al vuelo). Elige audio en el idioma preferido.
    func videoSource(for item: JFItem, preferredLanguage: String) async -> VideoSource? {
        guard let s = session else { return nil }
        let full = await details(item.id) ?? item
        let iso3 = Self.iso639_2(preferredLanguage)
        let streams = full.mediaStreams ?? []
        let audio = streams.first { $0.type == "Audio" && $0.language?.lowercased() == iso3 }
        var q = "MediaSourceId=\(item.id)&api_key=\(s.token)&DeviceId=\(deviceId)&VideoCodec=h264,hevc&AudioCodec=aac,mp3,ac3,eac3&TranscodingMaxAudioChannels=2&SegmentContainer=mp4&MaxStreamingBitrate=20000000"
        if let a = audio?.index { q += "&AudioStreamIndex=\(a)" }
        guard let url = URL(string: "\(s.server)/Videos/\(item.id)/master.m3u8?\(q)") else { return nil }

        // Subtítulos de texto en el idioma preferido (convertidos a SRT por el servidor)
        let textCodecs: Set<String> = ["subrip", "srt", "ass", "ssa", "webvtt", "vtt", "mov_text", "text"]
        let subs = streams.filter { $0.type == "Subtitle" && textCodecs.contains(($0.codec ?? "").lowercased()) }
        let sub = subs.first { $0.language?.lowercased() == iso3 } ?? (audio == nil ? subs.first : nil)
        var subURL: URL?
        if let idx = sub?.index {
            subURL = URL(string: "\(s.server)/Videos/\(item.id)/\(item.id)/Subtitles/\(idx)/0/Stream.srt?api_key=\(s.token)")
        }
        let title = item.type == "Episode" ? "\(item.seriesName ?? "") · \(item.name)" : item.name
        return VideoSource(id: "jf:" + item.id, title: title, url: url, subtitleURL: subURL, startAt: item.resumeSeconds)
    }

    func audioTrack(for item: JFItem) -> Track? {
        guard let s = session,
              let url = URL(string: "\(s.server)/Audio/\(item.id)/universal?UserId=\(s.userId)&DeviceId=\(deviceId)&api_key=\(s.token)&Container=mp3,aac,m4a,flac,alac,wav&TranscodingContainer=ts&TranscodingProtocol=hls&AudioCodec=aac")
        else { return nil }
        return Track(id: "jf:" + item.id, title: item.name, subtitle: item.albumArtist ?? "", url: url,
                     artworkURL: imageURL(item.id, height: 600))
    }

    func reportStopped(itemId: String, position: Double) async {
        guard let s = session, let url = URL(string: s.server + "/Sessions/Playing/Stopped") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader(token: s.token), forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["ItemId": itemId, "PositionTicks": Int64(position * 10_000_000)])
        _ = try? await URLSession.shared.data(for: req)
    }

    static func iso639_2(_ code: String) -> String {
        switch code {
        case "es": return "spa"
        case "en": return "eng"
        case "ca": return "cat"
        case "fr": return "fre"
        case "it": return "ita"
        case "pt": return "por"
        case "de": return "ger"
        default: return code
        }
    }
}
