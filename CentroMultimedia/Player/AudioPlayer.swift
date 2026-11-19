import Foundation
import AVFoundation
import MediaPlayer
import UIKit

struct Track: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var subtitle: String
    var url: URL
    var artworkURL: URL?
}

/// Reproductor de audio compartido: música, podcasts y audio de Jellyfin.
/// Sigue sonando en segundo plano y con la pantalla bloqueada.
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var shuffle = false
    @Published var repeatAll = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    /// Se llama cada vez que empieza una pista (para el historial).
    var onTrackStarted: ((Track) -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var originalOrder: [Track] = []
    private var artworkCache: [String: UIImage] = [:]

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var hasNext: Bool { index + 1 < queue.count || repeatAll }

    private init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            self.currentTime = t.seconds.isFinite ? t.seconds : 0
            if let d = self.player.currentItem?.duration.seconds, d.isFinite { self.duration = d }
        }
        setupRemoteCommands()
    }

    // MARK: Control

    func play(_ tracks: [Track], startAt i: Int = 0, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        originalOrder = tracks
        var start = min(max(0, i), tracks.count - 1)
        if shuffled {
            var rest = tracks
            let first = rest.remove(at: start)
            queue = [first] + rest.shuffled()
            start = 0
            shuffle = true
        } else {
            queue = tracks
            shuffle = false
        }
        index = start
        loadCurrent()
    }

    func toggle() {
        guard current != nil else { return }
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        activateSession()
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next() {
        if index + 1 < queue.count {
            index += 1
            loadCurrent()
        } else if repeatAll, !queue.isEmpty {
            index = 0
            loadCurrent()
        } else {
            pause()
            seek(to: 0)
        }
    }

    func previous() {
        if currentTime > 4 || index == 0 {
            seek(to: 0)
        } else {
            index -= 1
            loadCurrent()
        }
    }

    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        loadCurrent()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
        updateNowPlaying()
    }

    func skip(_ delta: Double) {
        seek(to: max(0, min(duration, currentTime + delta)))
    }

    func toggleShuffle() {
        guard let cur = current else { return }
        if shuffle {
            queue = originalOrder
            index = originalOrder.firstIndex(of: cur) ?? 0
            shuffle = false
        } else {
            var rest = queue
            rest.remove(at: index)
            queue = [cur] + rest.shuffled()
            index = 0
            shuffle = true
        }
    }

    func enqueue(_ tracks: [Track]) {
        if queue.isEmpty { play(tracks); return }
        queue.append(contentsOf: tracks)
        originalOrder.append(contentsOf: tracks)
    }

    // MARK: Interno

    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
    }

    private func loadCurrent() {
        guard let t = current else { return }
        activateSession()
        let item = AVPlayerItem(url: t.url)
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.next()
        }
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        currentTime = 0
        duration = 0
        updateNowPlaying()
        loadArtwork(for: t)
        onTrackStarted?(t)
    }

    private func loadArtwork(for t: Track) {
        guard let u = t.artworkURL, artworkCache[t.id] == nil else { return }
        if u.isFileURL {
            if let img = UIImage(contentsOfFile: u.path) { artworkCache[t.id] = img; updateNowPlaying() }
        } else {
            URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
                guard let data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self?.artworkCache[t.id] = img
                    self?.updateNowPlaying()
                }
            }.resume()
        }
    }

    private func updateNowPlaying() {
        guard let t = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let img = artworkCache[t.id] {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }
}
