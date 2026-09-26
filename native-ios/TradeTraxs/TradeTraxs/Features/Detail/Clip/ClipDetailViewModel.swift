import AVFoundation
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ClipDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var reel: Reel?
    private(set) var author: Profile?
    private(set) var authorAvatar: Image?
    private(set) var isOwner = false
    private(set) var isDeleting = false
    private(set) var deleteErrorMessage: String?
    private(set) var player: AVPlayer?
    private(set) var videoPresentation: VideoPresentationInfo?
    private(set) var didReachEnd = false

    let reelID: ReelID

    private let feed: any FeedRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let storage: any ObjectStorageProviding
    private let imagePipeline: any ImagePipeline
    private let cache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private var loadTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?
    private var consumptionTimeObserverToken: (player: AVPlayer, token: Any)?
    private var playerConfigurationGeneration: UInt64 = 0

    init(
        reelID: ReelID,
        feed: any FeedRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        storage: any ObjectStorageProviding,
        imagePipeline: any ImagePipeline,
        cache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.reelID = reelID
        self.feed = feed
        self.profiles = profiles
        self.session = session
        self.storage = storage
        self.imagePipeline = imagePipeline
        self.cache = cache
        self.navigationCoordinator = navigationCoordinator
    }

    var authorDisplayName: String { DetailAuthorPresentation.displayName(for: author) }
    var authorUsername: String { DetailAuthorPresentation.username(for: author) }
    var authorInitials: String { DetailAuthorPresentation.initials(for: author) }

    func tearDown() {
        playerConfigurationGeneration &+= 1
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let consumptionTimeObserverToken {
            consumptionTimeObserverToken.player.removeTimeObserver(consumptionTimeObserverToken.token)
            self.consumptionTimeObserverToken = nil
        }
        if let player {
            player.pause()
            ClipShortFormPlayerFactory.stopNetworkLoading(player)
            self.player = nil
        }
    }

    func suspendPlayback(reason: String) {
        guard let player else { return }
        player.pause()
        player.isMuted = true
        player.volume = 0
        ClipShortFormPlayerFactory.stopNetworkLoading(player)
        #if DEBUG
        print("[VIDEO_PLAYBACK] owner=clipDetail action=stop reason=\(reason)")
        #endif
    }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded || reel == nil else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        await performLoad(forceNetwork: true)
    }

    func replay() {
        guard let player else { return }
        ExperienceHaptics.play(.selection)
        didReachEnd = false
        player.seek(to: .zero)
        player.playImmediately(atRate: 1)
    }

    func deleteReel() async -> Bool {
        guard isOwner, !isDeleting else { return false }
        isDeleting = true
        deleteErrorMessage = nil
        defer { isDeleting = false }
        do {
            if let viewer = await session.currentUserID,
               viewer.rawValue.hasPrefix("dev.")
            {
                // Local development — mutate caches only.
            } else {
                try await feed.deleteReel(id: reelID)
            }
            tearDown()
            cache.removeReel(id: reelID)
            OwnerProfileOptimisticStore.shared.noteReelDeleted(id: reelID)
            ExperienceHaptics.play(.success)
            navigationCoordinator.pop()
            return true
        } catch {
            deleteErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    private func performLoad(forceNetwork: Bool = false) async {
        if !forceNetwork, let seed = cache.reel(id: reelID) {
            await apply(seed)
            loadTask = nil
            return
        }

        if reel == nil {
            phase = .loading
        }

        do {
            let result = try await feed.reel(id: reelID)
            guard !Task.isCancelled else { return }
            cache.seed(result.reel)
            if let embeddedTrade = result.embeddedTrade {
                cache.seed(embeddedTrade)
            }
            await apply(result.reel)
        } catch {
            guard !Task.isCancelled else { return }
            if reel == nil {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func apply(_ loaded: Reel) async {
        reel = loaded
        phase = .loaded
        let userID = await session.currentUserID
        isOwner = userID?.rawValue == loaded.authorProfileID.rawValue
        if let cached = cache.profile(id: loaded.authorProfileID) {
            author = cached
        } else {
            author = try? await SessionProfileStore.shared.profiles(
                ids: [loaded.authorProfileID],
                detailCache: cache,
                repository: profiles
            ).first
        }
        authorAvatar = await DetailAuthorPresentation.loadAvatar(
            for: author,
            imagePipeline: imagePipeline
        )
        configurePlayer(for: loaded)
    }

    private func configurePlayer(for reel: Reel) {
        guard let url = MediaURLResolver.url(
            for: reel.video,
            bucket: .reels,
            storage: storage
        ) else {
            return
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let consumptionTimeObserverToken {
            consumptionTimeObserverToken.player.removeTimeObserver(consumptionTimeObserverToken.token)
            self.consumptionTimeObserverToken = nil
        }
        if let player {
            player.pause()
            ClipShortFormPlayerFactory.stopNetworkLoading(player)
            self.player = nil
        }

        playerConfigurationGeneration &+= 1
        let configurationGeneration = playerConfigurationGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolved = await ClipVideoDeliveryService.shared.playbackURL(
                remoteURL: url,
                clipID: reel.id.rawValue,
                role: .detail
            )
            ClipVideoDeliveryTelemetry.record(.clipStart)
            let bufferSeconds = ClipPlaybackBufferConfiguration.make(
                for: ClipPlaybackLiveNetworkPosture().currentPosture()
            ).activeForwardBufferSeconds
            let built = ClipShortFormPlayerFactory.makePlayer(
                url: resolved.url,
                forwardBufferSeconds: bufferSeconds
            )
            guard self.playerConfigurationGeneration == configurationGeneration else {
                ClipShortFormPlayerFactory.stopNetworkLoading(built.player)
                return
            }
            let item = built.item
            let newPlayer = built.player
            self.player = newPlayer
            self.didReachEnd = false
            #if DEBUG
            MediaEgressTracker.installVideoAccessLog(
                on: item,
                mediaID: reel.id.rawValue,
                surface: "detail"
            )
            #endif

            self.endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.didReachEnd = true
                    ClipVideoDeliveryTelemetry.record(.clipCompletedView)
                }
            }

            newPlayer.playImmediately(atRate: 1)
            #if DEBUG
            print("[VIDEO_PLAYBACK] owner=clipDetail action=play")
            #endif

            let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
            let duration = reel.durationSeconds.map(Double.init)
            let consumptionToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                let watched = max(0, time.seconds)
                Task {
                    await ClipVideoDeliveryService.shared.updateConsumption(
                        clipID: reel.id.rawValue,
                        remoteURL: url,
                        watchedSeconds: watched,
                        durationSeconds: duration
                    )
                }
            }
            self.consumptionTimeObserverToken = (newPlayer, consumptionToken)

            if let info = await VideoPresentationInfo.load(url: resolved.url) {
                self.videoPresentation = info
                VideoPresentationProbe.log(
                    surface: .clipsPager,
                    info: info
                )
            }
        }
    }
}
