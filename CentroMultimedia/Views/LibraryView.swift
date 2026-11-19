import SwiftUI
import UniformTypeIdentifiers

enum LibrarySegment: String, CaseIterable, Identifiable {
    case movies = "Películas", shows = "Series", videos = "Vídeos", favorites = "Favoritos"
    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @State private var segment: LibrarySegment = .movies
    @State private var search = ""
    @State private var showImporter = false
    @State private var showLog = false
    @State private var confirmUndo = false

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 14)]

    private func matches(_ item: MediaItem) -> Bool {
        search.isEmpty || item.title.localizedCaseInsensitiveContains(search)
            || (item.show ?? "").localizedCaseInsensitiveContains(search)
            || (item.genre ?? "").localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Sección", selection: $segment) {
                    ForEach(LibrarySegment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if let s = library.metadataStatus {
                    Label(s, systemImage: "photo.on.rectangle.angled").font(.caption).foregroundColor(.orange).padding(.top, 6)
                }

                content.padding(.top, 8)
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $search, prompt: "Buscar título, serie o género")
            .refreshable { await library.refresh(settings: settings) }
            .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
            .navigationDestination(for: String.self) { SeriesView(show: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showImporter = true } label: { Label("Importar archivos", systemImage: "square.and.arrow.down") }
                        Button {
                            Task { await library.refresh(settings: settings, reorganizeAll: true) }
                        } label: { Label("Organizar ahora", systemImage: "wand.and.stars") }
                        Button { library.fetchMissingMetadata(force: true) } label: {
                            Label("Actualizar carátulas y sinopsis", systemImage: "photo.on.rectangle")
                        }
                        Button { confirmUndo = true } label: {
                            Label("Deshacer última organización", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!library.canUndo)
                        Button { showLog = true } label: { Label("Registro de cambios", systemImage: "list.bullet.rectangle") }
                    } label: {
                        if library.isScanning { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.movie, .audio, .video, .audiovisualContent, .item],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await library.importFiles(urls, settings: settings) }
                }
            }
            .confirmationDialog("¿Devolver los archivos de la última organización a su sitio anterior?",
                                isPresented: $confirmUndo, titleVisibility: .visible) {
                Button("Deshacer") { library.undoLastOrganization() }
            }
            .sheet(isPresented: $showLog) { OrganizerLogView() }
            .withMiniPlayer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .movies:
            let list = library.movies.filter(matches)
            if list.isEmpty { emptyState } else { grid(list) }
        case .shows:
            let shows = library.shows.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
            if shows.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(shows, id: \.self) { show in
                        let eps = library.episodes(of: show)
                        NavigationLink(value: show) {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkView(url: eps.first(where: { $0.artworkURL != nil })?.artworkURL, icon: "tv", title: show)
                                    .aspectRatio(2 / 3, contentMode: .fit)
                                Text(show).font(.caption.weight(.semibold)).lineLimit(2)
                                Text("\(eps.count) episodios").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        case .videos:
            let list = library.videos.filter(matches)
            if list.isEmpty { emptyState } else { grid(list) }
        case .favorites:
            let list = library.favorites.filter { $0.kind != .music && matches($0) }
            if list.isEmpty {
                EmptyStateView(icon: "heart", title: "Sin favoritos", message: "Marca películas, series o vídeos con el corazón para verlos aquí.")
            } else { grid(list) }
        }
    }

    private func grid(_ list: [MediaItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(list) { item in
                NavigationLink(value: item) {
                    PosterCard(item: item, progress: library.progress[item.id]?.fraction)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { library.toggleFavorite(item) } label: {
                        Label(item.isFavorite ? "Quitar de favoritos" : "Añadir a favoritos", systemImage: "heart")
                    }
                    AddToPlaylistMenu(item: item)
                }
            }
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            EmptyStateView(icon: "tray.and.arrow.down",
                           title: "Añade tus películas y series",
                           message: "Pulsa «Importar» o copia los archivos en la carpeta «Centro Multimedia › Entrada» desde la app Archivos o desde tu ordenador. Se clasificarán solos en Películas, Series, Música y Vídeos.")
            Button { showImporter = true } label: { Label("Importar archivos", systemImage: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Ficha

struct MediaDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: PlaybackRouter
    let item: MediaItem

    private var current: MediaItem { library.item(item.id) ?? item }

    var body: some View {
        let it = current
        let progress = library.progress[it.id]
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    ArtworkView(url: it.artworkURL, icon: it.kind.systemImage, title: it.title)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(width: 130)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(it.kind == .episode ? (it.show ?? it.title) : it.title).font(.title2.bold())
                        if it.kind == .episode { Text(it.displayTitle).foregroundColor(.secondary) }
                        if !it.subtitleLine.isEmpty && it.kind != .episode { Text(it.subtitleLine).foregroundColor(.secondary) }
                        if let d = it.duration { Text(formatDuration(d)).font(.subheadline).foregroundColor(.secondary) }
                        Text(it.fileExtension.uppercased()).font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                    }
                }

                HStack {
                    Button {
                        router.play([library.videoSource(for: it, language: settings.preferredLanguage)])
                    } label: {
                        Label(progress.map { $0.position > 30 && $0.fraction < 0.95 } == true
                              ? "Continuar (\(formatDuration(progress?.position)))" : "Reproducir",
                              systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button { library.toggleFavorite(it) } label: {
                        Image(systemName: it.isFavorite ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.bordered)
                }

                if !it.isNativelyPlayable {
                    Label("El formato \(it.fileExtension.uppercased()) puede no reproducirse en el reproductor de iOS. Si falla, añade este archivo a tu servidor Jellyfin (lo convierte al vuelo) o ábrelo con VLC desde «Compartir».",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundColor(.orange)
                }

                if let o = it.overview, !o.isEmpty {
                    Text(o).font(.body)
                }

                HStack {
                    AddToPlaylistMenu(item: it)
                    Spacer()
                    ShareLink(item: it.url) { Label("Compartir / Abrir en…", systemImage: "square.and.arrow.up") }
                }
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Archivo").font(.caption.bold()).foregroundColor(.secondary)
                    Text(it.relativePath).font(.caption.monospaced()).textSelection(.enabled)
                    Text(ByteCountFormatter.string(fromByteCount: it.fileSize, countStyle: .file)).font(.caption).foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(it.title)
        .navigationBarTitleDisplayMode(.inline)
        .withMiniPlayer()
    }
}

// MARK: - Serie

struct SeriesView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: PlaybackRouter
    let show: String

    var body: some View {
        let eps = library.episodes(of: show)
        let seasons = Array(Set(eps.map { $0.season ?? 1 })).sorted()
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    ArtworkView(url: eps.first(where: { $0.artworkURL != nil })?.artworkURL, icon: "tv", title: show)
                        .aspectRatio(2 / 3, contentMode: .fit).frame(width: 100)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(seasons.count) temporada\(seasons.count == 1 ? "" : "s") · \(eps.count) episodios")
                            .font(.subheadline).foregroundColor(.secondary)
                        if let o = eps.compactMap(\.overview).first { Text(o).font(.footnote).lineLimit(6) }
                        Button {
                            let next = eps.firstIndex { (library.progress[$0.id]?.fraction ?? 0) < 0.95 } ?? 0
                            playEpisodes(eps, from: next)
                        } label: { Label("Ver siguiente episodio", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            ForEach(seasons, id: \.self) { s in
                Section(String(format: "Temporada %d", s)) {
                    ForEach(eps.filter { ($0.season ?? 1) == s }) { ep in
                        Button {
                            playEpisodes(eps, from: eps.firstIndex(of: ep) ?? 0)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Episodio \(ep.episode ?? 0)").font(.subheadline.weight(.semibold))
                                    Text(formatDuration(ep.duration)).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if let p = library.progress[ep.id] {
                                    if p.fraction >= 0.95 {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                    } else {
                                        ProgressView(value: p.fraction).frame(width: 60)
                                    }
                                }
                            }
                        }
                        .foregroundColor(.primary)
                        .contextMenu { AddToPlaylistMenu(item: ep) }
                    }
                }
            }
        }
        .navigationTitle(show)
        .withMiniPlayer()
    }

    /// Reproduce desde un episodio y continúa con los siguientes.
    private func playEpisodes(_ eps: [MediaItem], from i: Int) {
        router.play(eps.map { library.videoSource(for: $0, language: settings.preferredLanguage) }, startAt: i)
    }
}

// MARK: - Registro del organizador

struct OrganizerLogView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let r = library.lastReport {
                    Section("Última revisión") {
                        Text(r.summary)
                        ForEach(r.errors, id: \.self) { Text($0).font(.footnote).foregroundColor(.orange) }
                    }
                }
                ForEach(library.batches.reversed()) { b in
                    Section(b.date.formatted(date: .abbreviated, time: .shortened)) {
                        ForEach(b.moves, id: \.self) { m in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.from).font(.caption.monospaced()).foregroundColor(.secondary)
                                Text("→ " + m.to).font(.caption.monospaced())
                            }
                        }
                    }
                }
                if library.batches.isEmpty {
                    Text("Todavía no se ha movido ningún archivo.").foregroundColor(.secondary)
                }
            }
            .navigationTitle("Registro")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
    }
}
