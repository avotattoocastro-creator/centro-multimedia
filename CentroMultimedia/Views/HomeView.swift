import SwiftUI

struct HomeView: View {
    @Binding var tab: Int
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var router: PlaybackRouter
    @Environment(\.openURL) private var openURL
    @State private var showSettings = false

    private var freeSpanishCinema: [CatalogEntry] {
        Catalog.entries.filter { $0.inSpanish && ($0.categories.contains(.movies) || $0.categories.contains(.spanishCinema)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    quickActions

                    if !library.continueWatching.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Continuar viendo")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(library.continueWatching) { item in
                                        Button { play(item) } label: {
                                            PosterCard(item: item, progress: library.progress[item.id]?.fraction)
                                                .frame(width: 120)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    if jellyfin.isLoggedIn && !jellyfin.resume.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Seguir en tu servidor") { tab = 2 }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(jellyfin.resume) { item in
                                        Button {
                                            Task {
                                                if let s = await jellyfin.videoSource(for: item, preferredLanguage: settings.preferredLanguage) {
                                                    router.play([s])
                                                }
                                            }
                                        } label: {
                                            JFCard(item: item).frame(width: 180)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Cine gratis en castellano") { tab = 4 }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(freeSpanishCinema) { e in
                                    Button { openURL(e.url) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Image(systemName: e.categories.first?.icon ?? "film")
                                                .font(.title2).foregroundColor(.orange)
                                            Text(e.name).font(.subheadline.bold()).lineLimit(2)
                                            Text(e.summary).font(.caption).foregroundColor(.secondary).lineLimit(3)
                                        }
                                        .frame(width: 190, height: 130, alignment: .topLeading)
                                        .padding(12)
                                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if !library.recentlyAdded.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Añadido recientemente") { tab = 1 }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(library.recentlyAdded) { item in
                                        Button { play(item) } label: {
                                            PosterCard(item: item).frame(width: 110)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    statsCard
                }
                .padding(.vertical)
            }
            .navigationTitle("Centro Multimedia")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .refreshable { await library.refresh(settings: settings) }
            .withMiniPlayer()
        }
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            QuickTile(icon: "film.stack", title: "Mi biblioteca", subtitle: "\(library.movies.count) películas · \(library.shows.count) series") { tab = 1 }
            QuickTile(icon: "server.rack", title: "Jellyfin", subtitle: jellyfin.isLoggedIn ? "Conectado" : "Conectar servidor") { tab = 2 }
            QuickTile(icon: "music.note", title: "Música", subtitle: "\(library.songs.count) canciones · \(library.podcasts.count) pódcast") { tab = 3 }
            QuickTile(icon: "sparkles.tv", title: "Descubrir", subtitle: "Gratis y legal") { tab = 4 }
        }
        .padding(.horizontal)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Organización automática", systemImage: "wand.and.stars").font(.headline)
            if library.isScanning {
                ProgressView("Revisando archivos…")
            } else if let r = library.lastReport {
                Text(r.summary).font(.subheadline)
                Text("Última revisión: \(r.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text("Añade archivos desde la pestaña Biblioteca o copiándolos a la carpeta «Entrada» de la app en Archivos.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            if let s = library.metadataStatus {
                Text(s).font(.caption).foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func play(_ item: MediaItem) {
        if item.kind == .music {
            AudioPlayer.shared.play([library.track(for: item)])
        } else if item.kind == .episode, let show = item.show {
            let eps = library.episodes(of: show)
            let i = eps.firstIndex(of: item) ?? 0
            router.play(eps.map { library.videoSource(for: $0, language: settings.preferredLanguage) }, startAt: i)
        } else {
            router.play([library.videoSource(for: item, language: settings.preferredLanguage)])
        }
    }
}

struct QuickTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.title2).foregroundColor(.orange)
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ajustes

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Idioma preferido", selection: $settings.preferredLanguage) {
                        ForEach(AppSettings.languages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Toggle("Mostrar solo contenido en castellano en Descubrir", isOn: $settings.onlySpanishCatalog)
                } header: {
                    Text("Idioma")
                } footer: {
                    Text("Se usa para elegir la pista de audio y los subtítulos, y para buscar títulos y carátulas en la tienda española.")
                }

                Section {
                    Toggle("Ordenar archivos automáticamente", isOn: $settings.autoOrganize)
                    Toggle("Renombrar archivos", isOn: $settings.renameFiles)
                    Toggle("Descargar carátulas y sinopsis", isOn: $settings.fetchMetadata)
                } header: {
                    Text("Biblioteca")
                } footer: {
                    Text("La app nunca borra archivos: los duplicados se apartan a «Biblioteca/Duplicados» y cualquier organización se puede deshacer.")
                }

                Section("Carpetas") {
                    Button {
                        let path = FileLocations.documents.path
                        if let url = URL(string: "shareddocuments://" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)) {
                            openURL(url)
                        }
                    } label: {
                        Label("Abrir la carpeta en Archivos", systemImage: "folder")
                    }
                    LabeledContent("Elementos en la biblioteca", value: "\(library.items.count)")
                    LabeledContent("Espacio usado", value: ByteCountFormatter.string(fromByteCount: library.items.reduce(0) { $0 + $1.fileSize }, countStyle: .file))
                }

                Section("Acerca de") {
                    Text("Centro Multimedia reproduce tus propios archivos y te enlaza con servicios gratuitos y legales. Usa solo contenido que te pertenezca o que tengas derecho a reproducir.")
                        .font(.footnote)
                    Text("Carátulas y sinopsis: API pública de búsqueda de Apple. Servidor: Jellyfin (código abierto).")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
    }
}
