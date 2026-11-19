import SwiftUI

enum MusicSegment: String, CaseIterable, Identifiable {
    case songs = "Canciones", artists = "Artistas", albums = "Álbumes", playlists = "Listas", podcasts = "Pódcast"
    var id: String { rawValue }
}

struct AlbumRef: Hashable {
    let name: String
    let artist: String
}

struct MusicView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var audio: AudioPlayer
    @State private var segment: MusicSegment = .songs
    @State private var search = ""
    @State private var showFreeSources = false
    @State private var path = NavigationPath()

    private var filteredSongs: [MediaItem] {
        library.songs.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || ($0.artist ?? "").localizedCaseInsensitiveContains(search)
                || ($0.album ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Picker("Sección", selection: $segment) {
                    ForEach(MusicSegment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                switch segment {
                case .songs: songsSection
                case .artists: artistsSection
                case .albums: albumsSection
                case .playlists: PlaylistsSection()
                case .podcasts: PodcastsSection()
                }
            }
            .listStyle(.plain)
            .navigationTitle("Música")
            .searchable(text: $search, prompt: "Canción, artista o álbum")
            .navigationDestination(for: Playlist.self) { PlaylistView(playlist: $0) }
            .navigationDestination(for: AlbumRef.self) { AlbumView(album: $0) }
            .navigationDestination(for: PodcastFeed.self) { PodcastFeedView(feed: $0) }
            .navigationDestination(for: MusicLink.self) { link in
                switch link {
                case .artist(let a): ArtistView(artist: a)
                case .favorites: SongListView(title: "Favoritos", songs: library.favorites.filter { $0.kind == .music })
                case .history: HistoryView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            AudioPlayer.shared.play(library.songs.map(library.track(for:)), shuffled: true)
                        } label: { Label("Reproducir todo en aleatorio", systemImage: "shuffle") }
                        Button { path.append(MusicLink.favorites) } label: { Label("Favoritos", systemImage: "heart") }
                        Button { path.append(MusicLink.history) } label: { Label("Historial", systemImage: "clock") }
                        Button { showFreeSources = true } label: { Label("Música gratis y legal", systemImage: "globe") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showFreeSources) { FreeSourcesSheet(category: .music) }
            .withMiniPlayer()
        }
    }

    @ViewBuilder
    private var songsSection: some View {
        let songs = filteredSongs
        if songs.isEmpty {
            EmptyStateView(icon: "music.note.list", title: "Tu música aparecerá aquí",
                           message: "Importa MP3, M4A, FLAC o WAV desde Biblioteca › Importar. Se ordenan solos por artista y álbum.")
                .listRowSeparator(.hidden)
        } else {
            HStack {
                Button { AudioPlayer.shared.play(songs.map(library.track(for:))) } label: {
                    Label("Reproducir", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                Button { AudioPlayer.shared.play(songs.map(library.track(for:)), shuffled: true) } label: {
                    Label("Aleatorio", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .listRowSeparator(.hidden)
            ForEach(Array(songs.enumerated()), id: \.element.id) { i, song in
                SongRow(song: song) { AudioPlayer.shared.play(songs.map(library.track(for:)), startAt: i) }
            }
        }
    }

    @ViewBuilder
    private var artistsSection: some View {
        ForEach(library.artists.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { a in
            NavigationLink(value: MusicLink.artist(a)) {
                HStack {
                    ArtworkView(url: library.songs(byArtist: a).first(where: { $0.artworkURL != nil })?.artworkURL,
                                icon: "music.mic", cornerRadius: 22)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text(a)
                        Text("\(library.songs(byArtist: a).count) canciones").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var albumsSection: some View {
        let albums = library.albums.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.artist.localizedCaseInsensitiveContains(search) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 16) {
            ForEach(albums) { album in
                NavigationLink(value: AlbumRef(name: album.name, artist: album.artist)) {
                    VStack(alignment: .leading, spacing: 4) {
                        ArtworkView(url: album.items.first(where: { $0.artworkURL != nil })?.artworkURL, icon: "opticaldisc", title: album.name)
                            .aspectRatio(1, contentMode: .fit)
                        Text(album.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(album.artist).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listRowSeparator(.hidden)
    }
}

enum MusicLink: Hashable {
    case artist(String), favorites, history
}

struct SongRow: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var audio: AudioPlayer
    let song: MediaItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ArtworkView(url: song.artworkURL, icon: "music.note", cornerRadius: 6).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).lineLimit(1)
                        .foregroundColor(audio.current?.id == song.id ? .orange : .primary)
                    Text(song.subtitleLine).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                if song.isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundColor(.orange) }
            }
        }
        .contextMenu {
            Button { library.toggleFavorite(song) } label: {
                Label(song.isFavorite ? "Quitar de favoritos" : "Añadir a favoritos", systemImage: "heart")
            }
            Button { audio.enqueue([library.track(for: song)]) } label: { Label("Añadir a la cola", systemImage: "text.append") }
            AddToPlaylistMenu(item: song)
        }
        .swipeActions(edge: .leading) {
            Button { library.toggleFavorite(song) } label: { Image(systemName: "heart") }.tint(.orange)
        }
    }
}

struct SongListView: View {
    @EnvironmentObject private var library: LibraryStore
    let title: String
    let songs: [MediaItem]

    var body: some View {
        List {
            if songs.isEmpty {
                Text("No hay canciones.").foregroundColor(.secondary)
            } else {
                Button { AudioPlayer.shared.play(songs.map(library.track(for:)), shuffled: true) } label: {
                    Label("Aleatorio", systemImage: "shuffle")
                }
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                    SongRow(song: s) { AudioPlayer.shared.play(songs.map(library.track(for:)), startAt: i) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .withMiniPlayer()
    }
}

struct ArtistView: View {
    @EnvironmentObject private var library: LibraryStore
    let artist: String
    var body: some View { SongListView(title: artist, songs: library.songs(byArtist: artist)) }
}

struct AlbumView: View {
    @EnvironmentObject private var library: LibraryStore
    let album: AlbumRef
    var body: some View {
        SongListView(title: album.name,
                     songs: library.songs.filter { ($0.album ?? "Sin álbum") == album.name && ($0.artist ?? "") == album.artist })
    }
}

struct HistoryView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        List {
            ForEach(library.history) { h in
                Button {
                    if let item = library.item(h.itemID) { AudioPlayer.shared.play([library.track(for: item)]) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.title).foregroundColor(.primary)
                        Text("\(h.subtitle) · \(h.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .disabled(library.item(h.itemID) == nil)
            }
        }
        .navigationTitle("Historial")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Borrar historial", role: .destructive) { library.clearHistory() }.disabled(library.history.isEmpty)
            }
        }
        .withMiniPlayer()
    }
}

// MARK: - Listas de reproducción

struct PlaylistsSection: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var askName = false
    @State private var name = ""

    var body: some View {
        Button { askName = true } label: { Label("Nueva lista", systemImage: "plus") }
            .alert("Nueva lista", isPresented: $askName) {
                TextField("Nombre", text: $name)
                Button("Crear") { library.createPlaylist(name); name = "" }
                Button("Cancelar", role: .cancel) { name = "" }
            }
        ForEach(library.playlists) { p in
            NavigationLink(value: p) {
                VStack(alignment: .leading) {
                    Text(p.name)
                    Text("\(p.itemIDs.count) elementos").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .onDelete { library.deletePlaylists(at: $0) }
    }
}

struct PlaylistView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: PlaybackRouter
    let playlist: Playlist

    private var current: Playlist { library.playlists.first { $0.id == playlist.id } ?? playlist }

    var body: some View {
        let items = library.items(in: current)
        List {
            HStack {
                Button { play(items, from: 0, shuffled: false) } label: { Label("Reproducir", systemImage: "play.fill").frame(maxWidth: .infinity) }
                Button { play(items, from: 0, shuffled: true) } label: { Label("Aleatorio", systemImage: "shuffle").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered)
            .disabled(items.isEmpty)

            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button { play(items, from: i, shuffled: false) } label: {
                    HStack {
                        Image(systemName: item.kind.systemImage).foregroundColor(.orange).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(item.kind == .episode ? "\(item.show ?? "") \(item.displayTitle)" : item.title).foregroundColor(.primary)
                            Text(item.subtitleLine).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .onDelete { library.removeFromPlaylist(current, at: $0) }
            .onMove { library.moveInPlaylist(current, from: $0, to: $1) }
        }
        .navigationTitle(current.name)
        .toolbar { EditButton() }
        .withMiniPlayer()
    }

    /// Las listas de audio van al reproductor de música; las de vídeo, al de vídeo (en orden).
    private func play(_ items: [MediaItem], from i: Int, shuffled: Bool) {
        guard !items.isEmpty else { return }
        let audioItems = items.filter { $0.kind == .music }
        if audioItems.count == items.count {
            AudioPlayer.shared.play(items.map(library.track(for:)), startAt: i, shuffled: shuffled)
        } else {
            let videos = shuffled ? items.filter { $0.kind != .music }.shuffled() : items.filter { $0.kind != .music }
            let start = shuffled ? 0 : (videos.firstIndex(of: items[i]) ?? 0)
            router.play(videos.map { library.videoSource(for: $0, language: settings.preferredLanguage) }, startAt: start)
        }
    }
}

// MARK: - Pódcast

struct PodcastsSection: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showAdd = false

    var body: some View {
        Button { showAdd = true } label: { Label("Buscar o añadir pódcast", systemImage: "plus.magnifyingglass") }
            .sheet(isPresented: $showAdd) { AddPodcastView() }
        ForEach(library.podcasts) { feed in
            NavigationLink(value: feed) {
                HStack {
                    ArtworkView(url: feed.artworkURL, icon: "mic", cornerRadius: 8).frame(width: 50, height: 50)
                    VStack(alignment: .leading) {
                        Text(feed.title).lineLimit(2)
                        Text("\(feed.episodes.count) episodios").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .onDelete { library.deletePodcasts(at: $0) }
        if !library.podcasts.isEmpty {
            Button { Task { await library.refreshPodcasts() } } label: { Label("Buscar episodios nuevos", systemImage: "arrow.clockwise") }
        }
    }
}

struct PodcastFeedView: View {
    @EnvironmentObject private var library: LibraryStore
    let feed: PodcastFeed

    private var current: PodcastFeed { library.podcasts.first { $0.feedURL == feed.feedURL } ?? feed }

    var body: some View {
        let f = current
        List {
            ForEach(Array(f.episodes.enumerated()), id: \.element.id) { i, ep in
                Button {
                    let tracks = f.episodes.map {
                        Track(id: $0.url.absoluteString, title: $0.title, subtitle: f.title, url: $0.url, artworkURL: f.artworkURL)
                    }
                    AudioPlayer.shared.play(tracks, startAt: i)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ep.title).foregroundColor(.primary).lineLimit(2)
                        Text([ep.date?.formatted(date: .abbreviated, time: .omitted), ep.duration].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(f.title)
        .refreshable { await library.refreshPodcasts() }
        .withMiniPlayer()
    }
}

struct AddPodcastView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ITunesResult] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Nombre del pódcast o dirección RSS", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Task { await go() } }
                    Button("Buscar") { Task { await go() } }.disabled(query.isEmpty || searching)
                    if let error { Text(error).font(.footnote).foregroundColor(.red) }
                } footer: {
                    Text("Búsqueda en el directorio público de pódcast (España). También puedes pegar una dirección RSS.")
                }
                if searching { ProgressView() }
                ForEach(results, id: \.feedUrl) { r in
                    Button {
                        Task {
                            if let s = r.feedUrl, let u = URL(string: s) {
                                do { try await library.subscribe(feedURL: u); dismiss() }
                                catch { self.error = "No se pudo leer ese pódcast." }
                            }
                        }
                    } label: {
                        HStack {
                            ArtworkView(url: (r.artworkUrl600 ?? r.artworkUrl100).flatMap(URL.init(string:)), icon: "mic", cornerRadius: 8)
                                .frame(width: 50, height: 50)
                            VStack(alignment: .leading) {
                                Text(r.collectionName ?? "Pódcast").foregroundColor(.primary)
                                Text(r.artistName ?? "").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Añadir pódcast")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
    }

    private func go() async {
        error = nil
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.lowercased().hasPrefix("http"), let u = URL(string: q) {
            do { try await library.subscribe(feedURL: u); dismiss() }
            catch { self.error = "No se pudo leer esa dirección RSS." }
            return
        }
        searching = true
        results = ((try? await PodcastService.search(q)) ?? []).filter { $0.feedUrl != nil }
        searching = false
        if results.isEmpty { error = "Sin resultados." }
    }
}
