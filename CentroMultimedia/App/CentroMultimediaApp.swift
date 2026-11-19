import SwiftUI
import AVFoundation

@main
struct CentroMultimediaApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var audio = AudioPlayer.shared
    @StateObject private var jellyfin = JellyfinStore()
    @StateObject private var router = PlaybackRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(audio)
                .environmentObject(jellyfin)
                .environmentObject(router)
        }
        .onChange(of: scenePhase) { phase in
            // Al volver a la app, la biblioteca se actualiza sola.
            if phase == .active {
                Task { await library.refresh(settings: settings) }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var router: PlaybackRouter
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab)
                .tabItem { Label("Inicio", systemImage: "house.fill") }.tag(0)
            LibraryView()
                .tabItem { Label("Biblioteca", systemImage: "film.stack") }.tag(1)
            JellyfinView()
                .tabItem { Label("Servidor", systemImage: "server.rack") }.tag(2)
            MusicView()
                .tabItem { Label("Música", systemImage: "music.note") }.tag(3)
            DiscoverView()
                .tabItem { Label("Descubrir", systemImage: "sparkles.tv") }.tag(4)
        }
        .tint(.orange)
        .task { await library.refresh(settings: settings) }
        .onAppear {
            audio.onTrackStarted = { track in
                Task { @MainActor in library.recordHistory(track) }
            }
        }
        .fullScreenCover(item: $router.request) { req in
            VideoPlayerScreen(request: req, preferredLanguage: settings.preferredLanguage) { source, pos, dur in
                Task { @MainActor in
                    if source.id.hasPrefix("jf:") {
                        await jellyfin.reportStopped(itemId: String(source.id.dropFirst(3)), position: pos)
                    } else {
                        library.recordProgress(id: source.id, position: pos, duration: dur)
                    }
                }
            }
        }
    }
}
