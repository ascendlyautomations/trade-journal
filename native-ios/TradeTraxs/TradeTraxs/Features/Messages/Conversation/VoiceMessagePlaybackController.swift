import AVFoundation
import Combine
import Foundation

@MainActor
final class VoiceMessagePlaybackController: ObservableObject {
    static let shared = VoiceMessagePlaybackController()

    @Published private(set) var activeMessageID: MessageID?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var cache = VoiceMessageAudioCache()

    private init() {}

    func toggle(messageID: MessageID, remoteURL: URL, knownDuration: TimeInterval?) {
        if activeMessageID == messageID, isPlaying {
            pause()
            return
        }
        if activeMessageID == messageID, !isPlaying, currentTime > 0, currentTime < duration {
            resume()
            return
        }
        Task { await play(messageID: messageID, remoteURL: remoteURL, knownDuration: knownDuration) }
    }

    func scrub(messageID: MessageID, progress: Double) {
        guard activeMessageID == messageID, duration > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        let target = duration * clamped
        currentTime = target
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func stopAll() {
        tearDownPlayer()
        activeMessageID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func play(messageID: MessageID, remoteURL: URL, knownDuration: TimeInterval?) async {
        stopAll()
        activeMessageID = messageID
        duration = knownDuration ?? 0

        do {
            let localURL = try await cache.localURL(for: remoteURL)
            let item = AVPlayerItem(url: localURL)
            let player = AVPlayer(playerItem: item)
            self.player = player

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePlaybackEnded()
                }
            }

            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentTime = time.seconds
                    if self.duration <= 0, item.duration.seconds.isFinite, item.duration.seconds > 0 {
                        self.duration = item.duration.seconds
                    }
                }
            }

            player.play()
            isPlaying = true
        } catch {
            stopAll()
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

    private func resume() {
        player?.play()
        isPlaying = true
    }

    private func handlePlaybackEnded() {
        isPlaying = false
        currentTime = duration
    }

    private func tearDownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
    }
}

private actor VoiceMessageAudioCache {
    private var inFlight: [URL: Task<URL, Error>] = [:]

    func localURL(for remoteURL: URL) async throws -> URL {
        let cached = cachedFileURL(for: remoteURL)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        if let task = inFlight[remoteURL] {
            return try await task.value
        }
        let task = Task<URL, Error> {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            try data.write(to: cached, options: .atomic)
            return cached
        }
        inFlight[remoteURL] = task
        defer { inFlight[remoteURL] = nil }
        return try await task.value
    }

    private func cachedFileURL(for remoteURL: URL) -> URL {
        let hash = String(remoteURL.absoluteString.hashValue)
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceMessages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(hash).m4a")
    }
}
