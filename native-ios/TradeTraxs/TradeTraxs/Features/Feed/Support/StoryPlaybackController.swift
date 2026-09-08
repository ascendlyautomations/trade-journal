import AVFoundation
import Foundation

/// Single authority for Story auto-advance — image timers, video completion, pause/resume.
@MainActor
final class StoryPlaybackController {
    enum PauseReason: Hashable {
        case hold
        case composer
        case background
    }

    static let imageDuration: TimeInterval = 7
    static let videoFallbackDuration: TimeInterval = 45

    private(set) var player: AVPlayer?

    var onAdvance: (() -> Void)?

    private let storage: any ObjectStorageProviding

    private var generation: UInt64 = 0
    private var activeStoryID: StoryID?
    private var isVideo = false

    private var imageElapsed: TimeInterval = 0
    private var imageTimerStartedAt: Date?
    private var imageTimerTask: Task<Void, Never>?

    private var videoFallbackTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?

    private var pauseReasons = Set<PauseReason>()

    init(storage: any ObjectStorageProviding) {
        self.storage = storage
    }

    var isPaused: Bool { !pauseReasons.isEmpty }

    func bind(story: Story) {
        stopPlayback()
        generation &+= 1
        let token = generation
        activeStoryID = story.id
        imageElapsed = 0
        imageTimerStartedAt = nil
        isVideo = Self.isVideoStory(story)

        if isVideo {
            guard let url = MediaURLResolver.url(for: story.media, bucket: .stories, storage: storage) else {
                scheduleVideoFallback(generation: token, duration: Self.videoFallbackDuration)
                return
            }
            startVideo(url: url, storyID: story.id, generation: token)
        } else {
            player = nil
            startImageTimer(generation: token)
        }
    }

    func pause(_ reason: PauseReason) {
        let inserted = pauseReasons.insert(reason).inserted
        guard inserted else { return }
        snapshotImageElapsed()
        cancelImageTimer()
        cancelVideoFallback()
        player?.pause()
    }

    func resume(_ reason: PauseReason) {
        pauseReasons.remove(reason)
        guard pauseReasons.isEmpty else { return }
        guard activeStoryID != nil else { return }
        let token = generation
        if isVideo {
            player?.play()
        } else {
            startImageTimer(generation: token)
        }
    }

    func stopPlayback() {
        generation &+= 1
        cancelImageTimer()
        cancelVideoFallback()
        removeEndObserver()
        player?.pause()
        player = nil
        activeStoryID = nil
        isVideo = false
        imageElapsed = 0
        imageTimerStartedAt = nil
        pauseReasons.removeAll()
    }

    // MARK: - Image

    private func startImageTimer(generation: UInt64) {
        cancelImageTimer()
        let remaining = Self.imageDuration - imageElapsed
        guard remaining > 0.02 else {
            completeIfCurrent(generation: generation)
            return
        }
        imageTimerStartedAt = Date()
        imageTimerTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard generation == self.generation, !self.isPaused else { return }
                self.completeIfCurrent(generation: generation)
            }
        }
    }

    private func snapshotImageElapsed() {
        if let started = imageTimerStartedAt {
            imageElapsed += Date().timeIntervalSince(started)
            imageTimerStartedAt = nil
        }
        imageElapsed = min(imageElapsed, Self.imageDuration)
    }

    private func cancelImageTimer() {
        snapshotImageElapsed()
        imageTimerTask?.cancel()
        imageTimerTask = nil
    }

    // MARK: - Video

    private func startVideo(url: URL, storyID: StoryID, generation: UInt64) {
        removeEndObserver()
        player?.pause()
        player = nil

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      generation == self.generation,
                      storyID == self.activeStoryID
                else { return }
                self.cancelVideoFallback()
                self.completeIfCurrent(generation: generation)
            }
        }

        Task {
            await waitForPlayableItem(item)
            guard generation == self.generation, storyID == self.activeStoryID else { return }
            let seconds = item.duration.seconds
            if !seconds.isFinite || seconds <= 0 {
                scheduleVideoFallback(generation: generation, duration: Self.videoFallbackDuration)
            }
            if !isPaused {
                newPlayer.play()
            }
        }
    }

    private func waitForPlayableItem(_ item: AVPlayerItem) async {
        for _ in 0..<40 {
            if item.status == .readyToPlay { return }
            if item.status == .failed { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func scheduleVideoFallback(generation: UInt64, duration: TimeInterval) {
        cancelVideoFallback()
        videoFallbackTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard generation == self.generation, !self.isPaused else { return }
                self.completeIfCurrent(generation: generation)
            }
        }
    }

    private func cancelVideoFallback() {
        videoFallbackTask?.cancel()
        videoFallbackTask = nil
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    // MARK: - Completion

    private func completeIfCurrent(generation: UInt64) {
        guard generation == self.generation, activeStoryID != nil, !isPaused else { return }
        onAdvance?()
    }

    // MARK: - Media kind

    static func isVideoStory(_ story: Story) -> Bool {
        if story.media.kind == .video { return true }
        let path = story.media.id.lowercased()
        for ext in [".mp4", ".mov", ".m4v", ".webm"] where path.hasSuffix(ext) {
            return true
        }
        return false
    }
}
