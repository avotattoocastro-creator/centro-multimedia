import SwiftUI

// MARK: - Imágenes

final class ImageCache {
    static let shared = NSCache<NSURL, UIImage>()
}

/// Muestra una carátula local o remota, con un marcador de posición si no hay imagen.
struct ArtworkView: View {
    let url: URL?
    var icon: String = "film"
    var title: String = ""
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let url, url.isFileURL, let img = Self.localImage(url) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let url, !url.isFileURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color.orange.opacity(0.75), Color.purple.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                if !title.isEmpty {
                    Text(title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3)
                        .padding(.horizontal, 6)
                }
            }
            .foregroundColor(.white)
        }
    }

    static func localImage(_ url: URL) -> UIImage? {
        if let img = ImageCache.shared.object(forKey: url as NSURL) { return img }
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        ImageCache.shared.setObject(img, forKey: url as NSURL)
        return img
    }
}

struct PosterCard: View {
    let item: MediaItem
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: item.artworkURL, icon: item.kind.systemImage, title: item.title)
                .aspectRatio(item.kind == .music ? 1 : 2 / 3, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    if let p = progress, p > 0 {
                        GeometryReader { g in
                            Capsule().fill(Color.orange).frame(width: g.size.width * p, height: 4)
                        }
                        .frame(height: 4)
                        .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item.isFavorite {
                        Image(systemName: "heart.fill").foregroundColor(.white).padding(6).shadow(radius: 2)
                    }
                }
            Text(item.kind == .episode ? (item.show ?? item.title) : item.title)
                .font(.caption.weight(.semibold)).lineLimit(2)
            if !item.subtitleLine.isEmpty || item.kind == .episode {
                Text(item.kind == .episode ? item.displayTitle : item.subtitleLine)
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionTitle = "Ver todo"

    var body: some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            if let action { Button(actionTitle, action: action).font(.subheadline) }
        }
        .padding(.horizontal)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44)).foregroundColor(.orange)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

func formatDuration(_ seconds: Double?) -> String {
    guard let s = seconds, s.isFinite, s > 0 else { return "" }
    let total = Int(s)
    let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
    return h > 0 ? String(format: "%d h %02d min", h, m) : String(format: "%d:%02d", m, sec)
}

// MARK: - Añadir a lista

struct AddToPlaylistMenu: View {
    @EnvironmentObject private var library: LibraryStore
    let item: MediaItem
    @State private var askName = false
    @State private var newName = ""

    var body: some View {
        Menu {
            ForEach(library.playlists) { p in
                Button(p.name) { library.add(item, to: p) }
            }
            Divider()
            Button { askName = true } label: { Label("Nueva lista…", systemImage: "plus") }
        } label: {
            Label("Añadir a lista", systemImage: "text.badge.plus")
        }
        .alert("Nueva lista", isPresented: $askName) {
            TextField("Nombre", text: $newName)
            Button("Crear") { library.createPlaylist(newName, with: item); newName = "" }
            Button("Cancelar", role: .cancel) { newName = "" }
        }
    }
}

// MARK: - Reproductor mínimo y pantalla "Reproduciendo"

struct MiniPlayerBar: View {
    @EnvironmentObject private var audio: AudioPlayer
    @State private var showFull = false

    var body: some View {
        if let t = audio.current {
            HStack(spacing: 12) {
                ArtworkView(url: t.artworkURL, icon: "music.note", cornerRadius: 6)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if !t.subtitle.isEmpty { Text(t.subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1) }
                }
                Spacer()
                Button { audio.toggle() } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                Button { audio.next() } label: { Image(systemName: "forward.fill").font(.title3) }
                    .disabled(!audio.hasNext)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottom) {
                GeometryReader { g in
                    Capsule().fill(Color.orange)
                        .frame(width: audio.duration > 0 ? g.size.width * audio.currentTime / audio.duration : 0, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 14)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture { showFull = true }
            .sheet(isPresented: $showFull) { NowPlayingView() }
        }
    }
}

extension View {
    /// Añade el reproductor mínimo encima de la barra de pestañas.
    func withMiniPlayer() -> some View {
        safeAreaInset(edge: .bottom) { MiniPlayerBar() }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var audio: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing: Double?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let t = audio.current {
                    ArtworkView(url: t.artworkURL, icon: "music.note", cornerRadius: 18)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 320)
                        .shadow(radius: 12)
                    VStack(spacing: 4) {
                        Text(t.title).font(.title3.bold()).multilineTextAlignment(.center)
                        Text(t.subtitle).foregroundColor(.secondary)
                    }
                    VStack {
                        Slider(value: Binding(get: { scrubbing ?? audio.currentTime },
                                              set: { scrubbing = $0 }),
                               in: 0...max(audio.duration, 1),
                               onEditingChanged: { editing in
                                   if !editing, let s = scrubbing { audio.seek(to: s); scrubbing = nil }
                               })
                        HStack {
                            Text(formatDuration(scrubbing ?? audio.currentTime))
                            Spacer()
                            Text(formatDuration(audio.duration))
                        }
                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                    }
                    HStack(spacing: 34) {
                        Button { audio.toggleShuffle() } label: {
                            Image(systemName: "shuffle").foregroundColor(audio.shuffle ? .orange : .secondary)
                        }
                        Button { audio.previous() } label: { Image(systemName: "backward.fill") }
                        Button { audio.toggle() } label: {
                            Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64))
                        }
                        Button { audio.next() } label: { Image(systemName: "forward.fill") }
                        Button { audio.repeatAll.toggle() } label: {
                            Image(systemName: "repeat").foregroundColor(audio.repeatAll ? .orange : .secondary)
                        }
                    }
                    .font(.title2)
                    .foregroundColor(.primary)
                    if audio.queue.count > 1 {
                        List {
                            Section("A continuación") {
                                ForEach(Array(audio.queue.enumerated()), id: \.offset) { i, track in
                                    Button { audio.jump(to: i) } label: {
                                        HStack {
                                            Text(track.title).lineLimit(1)
                                                .foregroundColor(i == audio.index ? .orange : .primary)
                                            Spacer()
                                            if i == audio.index { Image(systemName: "speaker.wave.2.fill").foregroundColor(.orange) }
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                    } else {
                        Spacer()
                    }
                } else {
                    EmptyStateView(icon: "music.note", title: "Nada sonando", message: "Elige una canción o un pódcast.")
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
            }
        }
    }
}
