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
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
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
        player.play()
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
            let loaded = try await feed.reel(id: reelID)
            guard !Task.isCancelled else { return }
            cache.seed(loaded)
            await apply(loaded)
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
        player?.pause()

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        didReachEnd = false

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.didReachEnd = true
            }
        }

        newPlayer.play()
    }
}
