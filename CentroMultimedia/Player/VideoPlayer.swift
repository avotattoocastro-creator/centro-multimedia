import SwiftUI
import AVKit

struct VideoSource: Identifiable, Equatable {
    let id: String
    let title: String
    let url: URL
    var subtitleURL: URL?
    var startAt: Double?
}

struct VideoRequest: Identifiable {
    let id = UUID()
    let sources: [VideoSource]
    let startIndex: Int
}

/// Centraliza la apertura del reproductor de vídeo a pantalla completa.
final class PlaybackRouter: ObservableObject {
    @Published var request: VideoRequest?

    func play(_ sources: [VideoSource], startAt i: Int = 0) {
        guard !sources.isEmpty else { return }
        AudioPlayer.shared.pause()
        request = VideoRequest(sources: sources, startIndex: min(max(0, i), sources.count - 1))
    }
}

// MARK: - Modelo

final class VideoPlaybackModel: ObservableObject {
    @Published private(set) var index: Int
    @Published var subtitleText = ""
    @Published var subtitlesOn = true
    @Published private(set) var hasSubtitles = false

    let sources: [VideoSource]
    let player = AVPlayer()
    private let onProgress: (VideoSource, Double, Double) -> Void
    private var cues: [SubtitleCue] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var ticks = 0
    private var started = false

    var current: VideoSource { sources[index] }

    init(sources: [VideoSource], startIndex: Int, preferredLanguage: String,
         onProgress: @escaping (VideoSource, Double, Double) -> Void) {
        self.sources = sources
        self.index = startIndex
        self.onProgress = onProgress
        player.appliesMediaSelectionCriteriaAutomatically = true
        player.setMediaSelectionCriteria(
            AVPlayerMediaSelectionCriteria(preferredLanguages: [preferredLanguage], preferredMediaCharacteristics: nil),
            forMediaCharacteristic: .audible)
    }

    func start() {
        guard !started else { return }
        started = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            self?.tick(t.seconds)
        }
        load(index)
    }

    func load(_ i: Int) {
        if player.currentItem != nil { saveProgress() }
        index = i
        let src = sources[i]
        let item = AVPlayerItem(url: src.url)
        player.replaceCurrentItem(with: item)
        cues = []
        subtitleText = ""
        hasSubtitles = false
        if let sub = src.subtitleURL { loadSubtitles(sub) }
        if let s = src.startAt, s > 5 { player.seek(to: CMTime(seconds: s, preferredTimescale: 600)) }
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.saveProgress()
            if self.index + 1 < self.sources.count { self.load(self.index + 1) }
        }
        player.play()
    }

    private func loadSubtitles(_ url: URL) {
        if url.isFileURL {
            if let d = try? Data(contentsOf: url) { cues = SubtitleParser.parse(data: d) }
            hasSubtitles = !cues.isEmpty
        } else {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data else { return }
                let parsed = SubtitleParser.parse(data: data)
                DispatchQueue.main.async {
                    self?.cues = parsed
                    self?.hasSubtitles = !parsed.isEmpty
                }
            }.resume()
        }
    }

    private func tick(_ t: Double) {
        guard t.isFinite else { return }
        if subtitlesOn, !cues.isEmpty {
            let text = cues.first { t >= $0.start && t <= $0.end }?.text ?? ""
            if text != subtitleText { subtitleText = text }
        } else if !subtitleText.isEmpty {
            subtitleText = ""
        }
        ticks += 1
        if ticks % 40 == 0 { saveProgress() }   // cada 10 s
    }

    func next() { if index + 1 < sources.count { load(index + 1) } }
    func previous() { if index > 0 { load(index - 1) } }

    func saveProgress() {
        guard let item = player.currentItem else { return }
        let pos = player.currentTime().seconds
        let dur = item.duration.seconds
        guard pos.isFinite else { return }
        onProgress(current, pos, dur.isFinite ? dur : 0)
    }

    func stop() {
        saveProgress()
        player.pause()
        if let o = timeObserver { player.removeTimeObserver(o); timeObserver = nil }
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
    }
}

// MARK: - Vistas

struct PlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}

struct VideoPlayerScreen: View {
    @StateObject private var model: VideoPlaybackModel
    @Environment(\.dismiss) private var dismiss

    init(request: VideoRequest, preferredLanguage: String, onProgress: @escaping (VideoSource, Double, Double) -> Void) {
        _model = StateObject(wrappedValue: VideoPlaybackModel(sources: request.sources, startIndex: request.startIndex,
                                                              preferredLanguage: preferredLanguage, onProgress: onProgress))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Button {
                    model.stop()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down").font(.title3.weight(.semibold))
                }
                .accessibilityLabel("Cerrar")

                Text(model.current.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if model.hasSubtitles {
                    Button { model.subtitlesOn.toggle() } label: {
                        Image(systemName: model.subtitlesOn ? "captions.bubble.fill" : "captions.bubble")
                    }
                    .accessibilityLabel("Subtítulos")
                }
                if model.sources.count > 1 {
                    Button { model.previous() } label: { Image(systemName: "backward.end.fill") }
                        .disabled(model.index == 0)
                    Text("\(model.index + 1)/\(model.sources.count)").font(.caption.monospacedDigit())
                    Button { model.next() } label: { Image(systemName: "forward.end.fill") }
                        .disabled(model.index + 1 >= model.sources.count)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal)
            .padding(.vertical, 10)

            ZStack(alignment: .bottom) {
                PlayerControllerView(player: model.player)
                if model.subtitlesOn && !model.subtitleText.isEmpty {
                    Text(model.subtitleText)
                        .font(.system(size: 20, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 70)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
