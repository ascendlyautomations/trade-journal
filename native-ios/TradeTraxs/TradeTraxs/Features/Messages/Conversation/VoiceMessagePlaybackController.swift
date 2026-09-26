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
        let messageIDRaw = messageID.rawValue

        do {
            let resolved = try await cache.resolveAudio(for: remoteURL)
            VoicePlaybackLog.prepare(
                VoicePlaybackPrepareFields(
                    messageID: messageIDRaw,
                    audioURL: remoteURL.absoluteString,
                    fileExtension: remoteURL.pathExtension.lowercased(),
                    declaredContentType: VoicePlaybackDiagnostics.declaredContentType(
                        for: remoteURL,
                        responseType: resolved.responseContentType
                    ),
                    source: resolved.source,
                    downloadBytes: resolved.downloadBytes,
                    httpStatus: resolved.httpStatus,
                    responseContentType: resolved.responseContentType,
                    cachedLocalPath: resolved.cachedLocalPath,
                    cachedFileExtension: resolved.cachedFileExtension,
                    remoteExtension: resolved.remoteExtension,
                    resolvedContainer: resolved.resolvedContainer,
                    cacheExtension: resolved.cacheExtension,
                    extensionMismatch: resolved.extensionMismatch
                )
            )

            let assetFields = await VoicePlaybackDiagnostics.inspectAsset(
                at: resolved.localURL,
                messageID: messageIDRaw
            )
            VoicePlaybackLog.asset(assetFields)

            let item = AVPlayerItem(url: resolved.localURL)
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

            await observePlayerItemStatus(messageID: messageIDRaw, item: item)

            player.play()
            isPlaying = true
        } catch {
            VoicePlaybackLog.player(
                messageID: messageIDRaw,
                playerItemStatus: "prepareFailed",
                playerError: String(describing: error)
            )
            stopAll()
        }
    }

    private func observePlayerItemStatus(messageID: String, item: AVPlayerItem) async {
        for _ in 0 ..< 24 {
            VoicePlaybackDiagnostics.logPlayerItem(messageID: messageID, item: item)
            if item.status != .unknown { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        VoicePlaybackDiagnostics.logPlayerItem(messageID: messageID, item: item)
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
    private var inFlight: [URL: Task<VoicePlaybackDiagnostics.ResolvedAudio, Error>] = [:]

    func resolveAudio(for remoteURL: URL) async throws -> VoicePlaybackDiagnostics.ResolvedAudio {
        if let task = inFlight[remoteURL] {
            return try await task.value
        }

        let task = Task<VoicePlaybackDiagnostics.ResolvedAudio, Error> {
            try await self.resolveAudioUncached(for: remoteURL)
        }
        inFlight[remoteURL] = task
        defer { inFlight[remoteURL] = nil }
        return try await task.value
    }

    private func resolveAudioUncached(for remoteURL: URL) async throws -> VoicePlaybackDiagnostics.ResolvedAudio {
        let hash = String(remoteURL.absoluteString.hashValue)
        let directory = cacheDirectory()
        let remoteExtLabel = VoicePlaybackCacheFormat.remoteExtension(from: remoteURL) ?? "none"

        if let remoteExt = VoicePlaybackCacheFormat.remoteExtension(from: remoteURL) {
            let cached = VoicePlaybackCacheFormat.cachePath(
                hash: hash,
                cacheExtension: remoteExt,
                directory: directory
            )
            if FileManager.default.fileExists(atPath: cached.path) {
                return makeCachedResult(
                    localURL: cached,
                    remoteURL: remoteURL,
                    remoteExtLabel: remoteExtLabel,
                    resolvedContainer: remoteExt,
                    cacheExtension: remoteExt
                )
            }
            let legacyM4A = VoicePlaybackCacheFormat.legacyForcedM4APath(hash: hash, directory: directory)
            if VoicePlaybackCacheFormat.shouldIgnoreLegacyM4ACache(remoteURL: remoteURL, legacyURL: legacyM4A),
               FileManager.default.fileExists(atPath: legacyM4A.path)
            {
                // Skip mismatched legacy WAV-bytes-at-.m4a entry — download to `.wav` below.
            }
        } else {
            for ext in ["m4a", "wav", "aac", "mp4", "caf"] {
                let candidate = VoicePlaybackCacheFormat.cachePath(
                    hash: hash,
                    cacheExtension: ext,
                    directory: directory
                )
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return makeCachedResult(
                        localURL: candidate,
                        remoteURL: remoteURL,
                        remoteExtLabel: remoteExtLabel,
                        resolvedContainer: ext,
                        cacheExtension: ext
                    )
                }
            }
        }

        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        let http = response as? HTTPURLResponse
        let contentType = http?.value(forHTTPHeaderField: "Content-Type")
        let resolved = VoicePlaybackCacheFormat.resolveCacheExtension(
            remoteURL: remoteURL,
            responseContentType: contentType,
            downloadedData: data
        )
        let cached = VoicePlaybackCacheFormat.cachePath(
            hash: hash,
            cacheExtension: resolved.cacheExtension,
            directory: directory
        )
        try data.write(to: cached, options: .atomic)

        return VoicePlaybackDiagnostics.ResolvedAudio(
            localURL: cached,
            source: "remote",
            downloadBytes: data.count,
            httpStatus: http?.statusCode,
            responseContentType: contentType,
            cachedLocalPath: cached.path,
            cachedFileExtension: cached.pathExtension.lowercased(),
            remoteExtension: remoteExtLabel,
            resolvedContainer: resolved.resolvedContainer,
            cacheExtension: resolved.cacheExtension,
            extensionMismatch: VoicePlaybackCacheFormat.extensionMismatch(
                remoteURL: remoteURL,
                cacheExtension: resolved.cacheExtension
            )
        )
    }

    private func makeCachedResult(
        localURL: URL,
        remoteURL: URL,
        remoteExtLabel: String,
        resolvedContainer: String,
        cacheExtension: String
    ) -> VoicePlaybackDiagnostics.ResolvedAudio {
        let bytes = (try? Data(contentsOf: localURL).count)
        return VoicePlaybackDiagnostics.ResolvedAudio(
            localURL: localURL,
            source: "cache",
            downloadBytes: bytes,
            httpStatus: nil,
            responseContentType: nil,
            cachedLocalPath: localURL.path,
            cachedFileExtension: localURL.pathExtension.lowercased(),
            remoteExtension: remoteExtLabel,
            resolvedContainer: resolvedContainer,
            cacheExtension: cacheExtension,
            extensionMismatch: VoicePlaybackCacheFormat.extensionMismatch(
                remoteURL: remoteURL,
                cacheExtension: cacheExtension
            )
        )
    }

    private func cacheDirectory() -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceMessages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
