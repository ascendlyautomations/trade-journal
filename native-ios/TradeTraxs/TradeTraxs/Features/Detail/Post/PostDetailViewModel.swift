import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class PostDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var post: Post?
    private(set) var author: Profile?
    private(set) var authorAvatar: Image?
    private(set) var isOwner = false
    private(set) var isDeleting = false
    private(set) var deleteErrorMessage: String?

    let postID: PostID

    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let imagePipeline: any ImagePipeline
    private let cache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private var loadTask: Task<Void, Never>?

    init(
        postID: PostID,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        imagePipeline: any ImagePipeline,
        cache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.postID = postID
        self.profiles = profiles
        self.session = session
        self.imagePipeline = imagePipeline
        self.cache = cache
        self.navigationCoordinator = navigationCoordinator
    }

    var authorDisplayName: String { DetailAuthorPresentation.displayName(for: author) }
    var authorUsername: String { DetailAuthorPresentation.username(for: author) }
    var authorInitials: String { DetailAuthorPresentation.initials(for: author) }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded || post == nil else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        await performLoad(forceNetwork: true)
    }

    func deletePost() async -> Bool {
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
                try await profiles.deleteWallPost(id: postID)
            }
            cache.removePost(id: postID)
            OwnerProfileOptimisticStore.shared.notePostDeleted(id: postID)
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
        if !forceNetwork, let seed = cache.post(id: postID) {
            post = seed
            phase = .loaded
            await loadAuthor(for: seed.authorProfileID)
            loadTask = nil
            return
        }

        if post == nil {
            phase = .loading
        }

        do {
            let loaded = try await profiles.wallPost(id: postID)
            guard !Task.isCancelled else { return }
            cache.seed(loaded)
            post = loaded
            phase = .loaded
            await loadAuthor(for: loaded.authorProfileID)
        } catch {
            guard !Task.isCancelled else { return }
            if post == nil {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func loadAuthor(for profileID: ProfileID) async {
        let userID = await session.currentUserID
        isOwner = userID?.rawValue == profileID.rawValue
        if let cached = cache.profile(id: profileID) {
            author = cached
        } else {
            author = try? await SessionProfileStore.shared.profiles(
                ids: [profileID],
                detailCache: cache,
                repository: profiles
            ).first
        }
        authorAvatar = await DetailAuthorPresentation.loadAvatar(
            for: author,
            imagePipeline: imagePipeline
        )
    }
}
