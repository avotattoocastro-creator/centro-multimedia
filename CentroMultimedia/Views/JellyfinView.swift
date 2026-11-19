import SwiftUI

struct JFCard: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let item: JFItem
    var wide = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: jellyfin.imageURL(item.id), icon: icon, title: item.name)
                .aspectRatio(wide ? 16 / 9 : 2 / 3, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    if let r = item.resumeSeconds, let t = item.runTimeTicks, t > 0 {
                        GeometryReader { g in
                            Capsule().fill(Color.orange)
                                .frame(width: g.size.width * min(1, r / (Double(t) / 10_000_000)), height: 4)
                        }
                        .frame(height: 4).padding(6)
                    }
                }
            Text(item.name).font(.caption.weight(.semibold)).lineLimit(2)
            if !item.subtitleLine.isEmpty {
                Text(item.subtitleLine).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
        }
    }

    private var icon: String {
        switch item.type {
        case "Audio", "MusicAlbum", "MusicArtist": return "music.note"
        case "Series", "Season", "Episode": return "tv"
        case "CollectionFolder", "Folder", "UserView": return "folder"
        default: return "film"
        }
    }
}

struct JellyfinView: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: PlaybackRouter
    @State private var search = ""
    @State private var results: [JFItem] = []

    var body: some View {
        NavigationStack {
            Group {
                if jellyfin.isLoggedIn { home } else { JellyfinLoginView() }
            }
            .navigationTitle("Servidor Jellyfin")
            .navigationDestination(for: JFItem.self) { JFFolderView(parent: $0) }
            .withMiniPlayer()
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !search.isEmpty {
                    JFGrid(items: results)
                } else {
                    if let e = jellyfin.errorMessage {
                        Label(e, systemImage: "wifi.exclamationmark").foregroundColor(.orange).padding(.horizontal)
                    }
                    if !jellyfin.resume.isEmpty { row("Continuar viendo", jellyfin.resume, wide: true) }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Bibliotecas")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(jellyfin.views) { v in
                                NavigationLink(value: v) { JFCard(item: v, wide: true) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    if !jellyfin.latest.isEmpty { row("Añadido recientemente", jellyfin.latest, wide: false) }
                }
            }
            .padding(.vertical)
        }
        .searchable(text: $search, prompt: "Buscar en el servidor")
        .onChange(of: search) { q in
            Task {
                let r = await jellyfin.search(q)
                if q == search { results = r }
            }
        }
        .refreshable { await jellyfin.loadHome() }
        .task { if jellyfin.views.isEmpty { await jellyfin.loadHome() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let s = jellyfin.session { Text("\(s.userName) · \(s.server)") }
                    Button(role: .destructive) { jellyfin.logout() } label: {
                        Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: { Image(systemName: "person.crop.circle") }
            }
        }
    }

    private func row(_ title: String, _ items: [JFItem], wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { item in
                        JFItemButton(item: item, siblings: items) { JFCard(item: item, wide: wide) }
                            .frame(width: wide ? 200 : 115)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Si el elemento se puede reproducir lo reproduce; si es una carpeta, navega dentro.
struct JFItemButton<Content: View>: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: PlaybackRouter
    let item: JFItem
    let siblings: [JFItem]
    @ViewBuilder let label: () -> Content
    @State private var loading = false

    var body: some View {
        if item.isPlayable {
            Button {
                Task { await play() }
            } label: {
                label().overlay { if loading { ProgressView() } }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) { label() }.buttonStyle(.plain)
        }
    }

    private func play() async {
        if item.isAudio {
            let tracks = siblings.filter(\.isAudio).compactMap { jellyfin.audioTrack(for: $0) }
            let i = tracks.firstIndex { $0.id == "jf:" + item.id } ?? 0
            AudioPlayer.shared.play(tracks, startAt: i)
            return
        }
        loading = true
        defer { loading = false }
        // En series, encadena los episodios siguientes de la misma temporada.
        let queue = item.type == "Episode" ? siblings.filter { $0.type == "Episode" } : [item]
        let start = queue.firstIndex(of: item) ?? 0
        var sources: [VideoSource] = []
        for (i, ep) in queue.enumerated() where i >= start && i < start + 10 {
            if let s = await jellyfin.videoSource(for: ep, preferredLanguage: settings.preferredLanguage) { sources.append(s) }
        }
        router.play(sources)
    }
}

struct JFGrid: View {
    let items: [JFItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 14)], spacing: 18) {
            ForEach(items) { item in
                JFItemButton(item: item, siblings: items) {
                    JFCard(item: item, wide: item.type == "Episode" || item.type == "Video" || item.type == "CollectionFolder")
                }
            }
        }
        .padding(.horizontal)
    }
}

struct JFFolderView: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let parent: JFItem
    @State private var items: [JFItem] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            if let o = parent.overview, !o.isEmpty {
                Text(o).font(.footnote).foregroundColor(.secondary).padding(.horizontal).padding(.bottom, 8)
            }
            if loading {
                ProgressView().padding(40)
            } else if items.isEmpty {
                EmptyStateView(icon: "tray", title: "Carpeta vacía", message: "No hay contenido aquí.")
            } else if items.allSatisfy(\.isAudio) {
                VStack(spacing: 0) {
                    Button {
                        let tracks = items.compactMap { jellyfin.audioTrack(for: $0) }
                        AudioPlayer.shared.play(tracks, shuffled: true)
                    } label: { Label("Aleatorio", systemImage: "shuffle").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).padding()
                    ForEach(items) { song in
                        JFItemButton(item: song, siblings: items) {
                            HStack {
                                Text(song.indexNumber.map { "\($0)" } ?? "").font(.caption.monospacedDigit()).frame(width: 24)
                                Text(song.name).lineLimit(1)
                                Spacer()
                                Text(formatDuration(song.runTimeTicks.map { Double($0) / 10_000_000 }))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            .padding(.horizontal).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        Divider().padding(.leading)
                    }
                }
            } else {
                JFGrid(items: items)
            }
        }
        .navigationTitle(parent.name)
        .task {
            items = await jellyfin.children(of: parent)
            loading = false
        }
        .withMiniPlayer()
    }
}

struct JellyfinLoginView: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @AppStorage("jellyfin.lastServer") private var server = ""
    @State private var user = ""
    @State private var password = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                TextField("http://192.168.1.20:8096", text: $server)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Usuario", text: $user)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Contraseña", text: $password)
                Button {
                    Task { await jellyfin.login(server: server, user: user, password: password) }
                } label: {
                    if jellyfin.isLoading { ProgressView() } else { Text("Conectar") }
                }
                .disabled(server.isEmpty || user.isEmpty || jellyfin.isLoading)
                if let e = jellyfin.errorMessage { Text(e).font(.footnote).foregroundColor(.red) }
            } header: {
                Text("Conecta tu servidor")
            } footer: {
                Text("Jellyfin es un servidor multimedia gratuito y de código abierto. Instálalo en tu portátil, apúntalo a tus carpetas de películas, series y música, y míralas aquí desde cualquier dispositivo de tu red, con carátulas, sinopsis, temporadas y búsqueda.")
            }

            Section("Cómo empezar (10 minutos)") {
                Label("Descarga Jellyfin Server para Windows, macOS o Linux.", systemImage: "1.circle")
                Label("Crea tu usuario y añade bibliotecas: Películas, Series y Música. Elige «Español (España)» como idioma de metadatos.", systemImage: "2.circle")
                Label("Copia aquí la dirección que muestra el panel (p. ej. http://192.168.1.20:8096).", systemImage: "3.circle")
                Button("Descargar Jellyfin Server") { openURL(URL(string: "https://jellyfin.org/downloads/server")!) }
            }
        }
    }
}
