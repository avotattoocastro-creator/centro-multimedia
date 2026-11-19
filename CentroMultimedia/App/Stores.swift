import Foundation
import SwiftUI

// MARK: - Ajustes

final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var autoOrganize: Bool { didSet { d.set(autoOrganize, forKey: "autoOrganize") } }
    @Published var renameFiles: Bool { didSet { d.set(renameFiles, forKey: "renameFiles") } }
    @Published var fetchMetadata: Bool { didSet { d.set(fetchMetadata, forKey: "fetchMetadata") } }
    @Published var preferredLanguage: String { didSet { d.set(preferredLanguage, forKey: "preferredLanguage") } }
    @Published var onlySpanishCatalog: Bool { didSet { d.set(onlySpanishCatalog, forKey: "onlySpanishCatalog") } }

    struct LanguageOption: Hashable {
        let code: String
        let name: String
    }

    static let languages: [LanguageOption] = [
        LanguageOption(code: "es", name: "Castellano"), LanguageOption(code: "ca", name: "Catalán"),
        LanguageOption(code: "en", name: "Inglés"), LanguageOption(code: "fr", name: "Francés"),
        LanguageOption(code: "it", name: "Italiano"), LanguageOption(code: "pt", name: "Portugués"),
    ]

    init() {
        d.register(defaults: ["autoOrganize": true, "renameFiles": true, "fetchMetadata": true,
                              "preferredLanguage": "es", "onlySpanishCatalog": true])
        autoOrganize = d.bool(forKey: "autoOrganize")
        renameFiles = d.bool(forKey: "renameFiles")
        fetchMetadata = d.bool(forKey: "fetchMetadata")
        preferredLanguage = d.string(forKey: "preferredLanguage") ?? "es"
        onlySpanishCatalog = d.bool(forKey: "onlySpanishCatalog")
    }
}

// MARK: - Biblioteca

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published var playlists: [Playlist] = []
    @Published private(set) var progress: [String: PlaybackProgress] = [:]
    @Published private(set) var history: [HistoryEntry] = []
    @Published var favoriteCatalogIDs: Set<String> = []
    @Published var customEntries: [CatalogEntry] = []
    @Published var podcasts: [PodcastFeed] = []
    @Published private(set) var batches: [OrganizeBatch] = []
    @Published private(set) var lastReport: ScanReport?
    @Published private(set) var isScanning = false
    @Published private(set) var metadataStatus: String?

    private var pinnedPaths: Set<String> = []
    private var metadataTask: Task<Void, Never>?
    private var stateURL: URL { FileLocations.support.appendingPathComponent("estado.json") }

    init() {
        load()
    }

    // MARK: Persistencia

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        items = s.items
        playlists = s.playlists
        progress = s.progress
        history = s.history
        favoriteCatalogIDs = s.favoriteCatalogIDs
        customEntries = s.customEntries
        podcasts = s.podcasts
        batches = s.batches
        pinnedPaths = s.pinnedPaths
        lastReport = s.lastReport
    }

    func save() {
        var s = PersistedState()
        s.items = items
        s.playlists = playlists
        s.progress = progress
        s.history = Array(history.prefix(300))
        s.favoriteCatalogIDs = favoriteCatalogIDs
        s.customEntries = customEntries
        s.podcasts = podcasts
        s.batches = Array(batches.suffix(20))
        s.pinnedPaths = pinnedPaths
        s.lastReport = lastReport
        guard let data = try? JSONEncoder().encode(s) else { return }
        let url = stateURL
        Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: Escaneo y organización

    /// Revisa la carpeta de la app: detecta archivos nuevos, los clasifica, aparta duplicados
    /// y (si está activado) los ordena en carpetas. Nunca borra nada.
    func refresh(settings: AppSettings, reorganizeAll: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        if reorganizeAll { pinnedPaths = [] }
        let options = OrganizeOptions(organize: settings.autoOrganize || reorganizeAll,
                                      rename: settings.renameFiles, reorganizeKnown: reorganizeAll)
        let known = items
        let pinned = pinnedPaths
        let result = await Task.detached(priority: .userInitiated) {
            await FileOrganizer.scan(known: known, pinned: pinned, options: options)
        }.value

        var updated = items.filter { !result.missingIDs.contains($0.id) }
        for i in updated.indices {
            if let p = result.pathUpdates[updated[i].id] { updated[i].relativePath = p }
        }
        updated.append(contentsOf: result.newItems)
        items = updated
        if let b = result.batch { batches.append(b) }
        let changed = result.report.added + result.report.moved + result.report.duplicates + result.report.missing > 0
        if changed || lastReport == nil || reorganizeAll { lastReport = result.report }
        isScanning = false
        save()
        if settings.fetchMetadata { fetchMissingMetadata() }
    }

    func importFiles(_ urls: [URL], settings: AppSettings) async {
        FileLocations.ensureFolders()
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let dest = FileOrganizer.uniqueURL(FileLocations.inbox.appendingPathComponent(url.lastPathComponent))
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        await refresh(settings: settings)
    }

    var canUndo: Bool { !batches.isEmpty }

    func undoLastOrganization() {
        guard let last = batches.popLast() else { return }
        let restored = FileOrganizer.undo(last)
        for i in items.indices {
            if let back = restored[items[i].relativePath] { items[i].relativePath = back }
        }
        // Lo devuelto a su sitio no se vuelve a mover automáticamente.
        pinnedPaths.formUnion(restored.values)
        lastReport = ScanReport(date: Date(), added: 0, duplicates: 0, moved: 0, missing: 0,
                                errors: restored.isEmpty ? ["No había nada que deshacer."] : ["Se han devuelto \(restored.count) archivos a su ubicación anterior."])
        save()
    }

    // MARK: Metadatos

    func fetchMissingMetadata(force: Bool = false) {
        guard metadataTask == nil else { return }
        let pending = items.filter { $0.kind != .video && (force || !$0.metadataChecked) }
        guard !pending.isEmpty else { return }
        metadataTask = Task { [weak self] in
            var showCache: [String: MetadataService.Found?] = [:]
            var done = 0
            for item in pending {
                if Task.isCancelled { break }
                self?.metadataStatus = "Buscando carátulas y sinopsis… \(done + 1)/\(pending.count)"
                var found: MetadataService.Found?
                if item.kind == .episode, let show = item.show, let cached = showCache[show] {
                    found = cached
                } else {
                    found = await MetadataService.lookup(item)
                    if item.kind == .episode, let show = item.show { showCache[show] = found }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)   // respeta el límite de la API
                }
                var art: String?
                if let f = found, let u = f.artworkURL, item.artworkFile == nil || force,
                   let data = await MetadataService.download(u) {
                    art = FileOrganizer.saveArtwork(data, id: item.id)
                }
                self?.applyMetadata(id: item.id, found: found, artwork: art)
                done += 1
            }
            self?.metadataStatus = nil
            self?.metadataTask = nil
            self?.save()
        }
    }

    private func applyMetadata(id: String, found: MetadataService.Found?, artwork: String?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].metadataChecked = true
        if let f = found {
            if let o = f.overview, !o.isEmpty { items[i].overview = o }
            if let g = f.genre { items[i].genre = g }
            if items[i].year == nil, let y = f.year { items[i].year = y }
        }
        if let a = artwork { items[i].artworkFile = a }
    }

    // MARK: Consultas

    var movies: [MediaItem] { items.filter { $0.kind == .movie }.sorted { $0.title.localizedCompare($1.title) == .orderedAscending } }
    var videos: [MediaItem] { items.filter { $0.kind == .video }.sorted { $0.addedAt > $1.addedAt } }
    var songs: [MediaItem] { items.filter { $0.kind == .music }.sorted { $0.title.localizedCompare($1.title) == .orderedAscending } }

    var shows: [String] {
        Array(Set(items.compactMap { $0.kind == .episode ? $0.show : nil })).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    func episodes(of show: String) -> [MediaItem] {
        items.filter { $0.kind == .episode && $0.show == show }
            .sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
    }

    var artists: [String] {
        Array(Set(songs.map { $0.artist ?? "Artista desconocido" })).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    func songs(byArtist a: String) -> [MediaItem] { songs.filter { ($0.artist ?? "Artista desconocido") == a } }

    struct AlbumGroup: Identifiable {
        var id: String { name + "\u{1}" + artist }
        let name: String
        let artist: String
        let items: [MediaItem]
    }

    var albums: [AlbumGroup] {
        let groups = Dictionary(grouping: songs) { "\($0.album ?? "Sin álbum")\u{1}\($0.artist ?? "")" }
        return groups.map { key, value in
            let parts = key.components(separatedBy: "\u{1}")
            return AlbumGroup(name: parts[0], artist: parts.count > 1 ? parts[1] : "", items: value)
        }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var continueWatching: [MediaItem] {
        items.filter { item in
            guard item.kind != .music, let p = progress[item.id] else { return false }
            return p.position > 30 && p.fraction < 0.95
        }.sorted { (progress[$0.id]?.updated ?? .distantPast) > (progress[$1.id]?.updated ?? .distantPast) }
    }

    var recentlyAdded: [MediaItem] { Array(items.sorted { $0.addedAt > $1.addedAt }.prefix(15)) }
    var favorites: [MediaItem] { items.filter(\.isFavorite) }

    func item(_ id: String) -> MediaItem? { items.first { $0.id == id } }

    // MARK: Favoritos, listas, historial, progreso

    func toggleFavorite(_ item: MediaItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].isFavorite.toggle()
        save()
    }

    func createPlaylist(_ name: String, with item: MediaItem? = nil) {
        var p = Playlist(name: name.isEmpty ? "Nueva lista" : name)
        if let item { p.itemIDs.append(item.id) }
        playlists.append(p)
        save()
    }

    func add(_ item: MediaItem, to playlist: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        if !playlists[i].itemIDs.contains(item.id) { playlists[i].itemIDs.append(item.id) }
        save()
    }

    func items(in playlist: Playlist) -> [MediaItem] { playlist.itemIDs.compactMap { item($0) } }

    func deletePlaylists(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        save()
    }

    func removeFromPlaylist(_ playlist: Playlist, at offsets: IndexSet) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i].itemIDs.remove(atOffsets: offsets)
        save()
    }

    func moveInPlaylist(_ playlist: Playlist, from: IndexSet, to: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i].itemIDs.move(fromOffsets: from, toOffset: to)
        save()
    }

    func recordHistory(_ track: Track) {
        history.insert(HistoryEntry(itemID: track.id, title: track.title, subtitle: track.subtitle, date: Date()), at: 0)
        if history.count > 300 { history.removeLast(history.count - 300) }
        save()
    }

    func recordProgress(id: String, position: Double, duration: Double) {
        progress[id] = PlaybackProgress(position: position, duration: duration, updated: Date())
        save()
    }

    func clearHistory() {
        history = []
        save()
    }

    // MARK: Conversión a pistas/vídeos

    nonisolated func track(for item: MediaItem) -> Track {
        Track(id: item.id, title: item.title, subtitle: item.artist ?? item.album ?? "", url: item.url, artworkURL: item.artworkURL)
    }

    func videoSource(for item: MediaItem, language: String) -> VideoSource {
        let start = progress[item.id].flatMap { $0.fraction < 0.95 ? $0.position : nil }
        let title = item.kind == .episode ? "\(item.show ?? "") · \(item.displayTitle)" : item.title
        return VideoSource(id: item.id, title: title, url: item.url,
                           subtitleURL: FileOrganizer.subtitles(for: item.url, preferredLanguage: language),
                           startAt: start)
    }

    // MARK: Catálogo y podcasts

    var allCatalogEntries: [CatalogEntry] { Catalog.entries + customEntries }

    func toggleCatalogFavorite(_ e: CatalogEntry) {
        if favoriteCatalogIDs.contains(e.id) { favoriteCatalogIDs.remove(e.id) } else { favoriteCatalogIDs.insert(e.id) }
        save()
    }

    func addCustomEntry(name: String, url: URL, category: CatalogCategory, notes: String) {
        let e = CatalogEntry(id: "custom-" + UUID().uuidString, name: name, categories: [category],
                             languages: ["Castellano"], duration: .mixed, topics: [], summary: notes,
                             registration: "—", limitations: "—", url: url, isCustom: true)
        customEntries.append(e)
        favoriteCatalogIDs.insert(e.id)
        save()
    }

    func deleteCustomEntry(_ e: CatalogEntry) {
        customEntries.removeAll { $0.id == e.id }
        favoriteCatalogIDs.remove(e.id)
        save()
    }

    func subscribe(feedURL: URL) async throws {
        let feed = try await PodcastService.fetch(feedURL)
        podcasts.removeAll { $0.feedURL == feedURL }
        podcasts.append(feed)
        save()
    }

    func refreshPodcasts() async {
        for feed in podcasts {
            if let f = try? await PodcastService.fetch(feed.feedURL),
               let i = podcasts.firstIndex(where: { $0.feedURL == feed.feedURL }) {
                podcasts[i] = f
            }
        }
        save()
    }

    func deletePodcasts(at offsets: IndexSet) {
        podcasts.remove(atOffsets: offsets)
        save()
    }
}
