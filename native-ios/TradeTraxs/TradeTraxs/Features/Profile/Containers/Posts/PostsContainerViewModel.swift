import Foundation
import Observation

@Observable
@MainActor
final class PostsContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var items: [Post] = []

    let profileOwnerID: ProfileID
    private(set) var isOwner: Bool
    var pendingDelete: Post?
    var deleteErrorMessage: String?
    private(set) var deletingPostID: PostID?
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let rpc: (any RPCClient)?
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore?
    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var nextCursor: String?
    private var isLoadingMore = false
    private var paginationGeneration = 0
    private var hasLoaded = false
    private var isScreenOwned = false
    private var awaitingScreenBootstrap = false
    private let initialLoadFailureGrace = ProfileSectionFailureGrace()
    private var syncGeneration: UInt64 = 0

    /// True after an authoritative section fetch or complete bootstrap snapshot.
    var hasAuthoritativePayload: Bool { hasLoaded }

    init(
        profileID: ProfileID,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        rpc: (any RPCClient)? = nil,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil,
        isOwner: Bool = true
    ) {
        self.profileOwnerID = profileID
        self.isOwner = isOwner
        self.profiles = profiles
        self.session = session
        self.rpc = rpc
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.engagementStore = engagementStore
    }

    func prefetchEngagement(for postIDs: [PostID]) {
        let targets = postIDs.map { InteractionTarget.profilePost($0) }
        guard !targets.isEmpty else { return }
        engagementStore?.prefetch(targets)
    }

    func applyBootstrap(_ snapshot: ProfileState) {
        if snapshot.didBootstrap || snapshot.phase == .loaded {
            isScreenOwned = true
        }
        awaitingScreenBootstrap = ProfileSectionInitialLoad.awaitingScreenBootstrap(
            isScreenOwned: isScreenOwned,
            snapshot: snapshot,
            didLoadSection: snapshot.didLoadPosts,
            sectionItemsEmpty: snapshot.posts.isEmpty,
            localItemsEmpty: items.isEmpty
        )
        let beforeCount = items.count
        guard snapshot.didLoadPosts || !snapshot.posts.isEmpty else {
            let plan = ProfileSectionInitialLoad.planWhenBootstrapOmitsSectionPayload(
                snapshot: snapshot,
                hasLoaded: hasLoaded,
                itemsEmpty: items.isEmpty,
                itemCount: items.count,
                currentState: state,
                awaitingScreenBootstrap: awaitingScreenBootstrap
            )
            ProfileSectionInitialLoad.applyBootstrapMissingSectionPlan(
                plan,
                setState: { [self] next in state = next },
                kickDeferredLoad: { [self] in loadIfNeeded() }
            )
            return
        }

        awaitingScreenBootstrap = false
        initialLoadFailureGrace.cancel()

        if hasLoaded {
            if snapshot.posts.isEmpty {
                if items.isEmpty, snapshot.didLoadPosts {
                    detailCache.seed(posts: [])
                    state = .empty
                    prefetchEngagement(for: [])
                }
                return
            }
            mergeIncomingPosts(snapshot.posts)
            #if DEBUG
            ProfilePostsSync.logReconciled(
                beforeCount: beforeCount,
                snapshotCount: snapshot.posts.count,
                afterCount: items.count
            )
            ProfilePostsSync.logUIVisibleCount(items.count)
            #endif
            detailCache.seed(posts: items)
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            return
        }

        if items.isEmpty {
            items = excludingDeletedPosts(sortedPosts(snapshot.posts))
        } else {
            mergeIncomingPosts(snapshot.posts)
        }
        hasLoaded = true
        #if DEBUG
        ProfilePostsSync.logReconciled(
            beforeCount: beforeCount,
            snapshotCount: snapshot.posts.count,
            afterCount: items.count
        )
        ProfilePostsSync.logUIVisibleCount(items.count)
        #endif
        detailCache.seed(posts: items)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))
        ProfileTabLoadProbe.cache(.posts, count: items.count)
        ProfileTabLoadProbe.state(.posts, loaded: hasLoaded, loading: state.isLoading, count: items.count)
    }

    /// Web or another device published or edited this post. Keep every other post.
    /// Does not mark an unloaded tab as loaded — one row must not replace the page fetch.
    func noteRemoteUpsert(_ post: Post) {
        guard post.authorProfileID == profileOwnerID else { return }
        mergeIncomingPosts([post])
        guard hasLoaded else { return }
        detailCache.seed(posts: items)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: [post.id])
        if isOwner {
            OwnerProfileOptimisticStore.shared.syncOwnerPostsState(items)
        }
    }

    /// A delete from the web or another device. Only this id leaves the list.
    func noteRemoteDeleted(id: PostID) {
        items.removeAll { $0.id == id }
        detailCache.removePost(id: id)
        guard hasLoaded else { return }
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        if isOwner {
            OwnerProfileOptimisticStore.shared.syncOwnerPostsState(items)
        }
    }

    /// Owner delete — drop from grid immediately.
    func noteDeleteSucceeded(id: PostID) {
        items.removeAll { $0.id == id }
        detailCache.removePost(id: id)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))
        OwnerProfileOptimisticStore.shared.syncOwnerPostsState(items)
    }

    /// Owner publish — upsert immediately, then refresh page 1 using the same path as manual reload.
    func notePublishSucceeded(_ post: Post, preservingExisting existingItems: [Post] = []) {
        guard post.authorProfileID == profileOwnerID else { return }
        let visibleBefore = items.count
        let baseline = items.isEmpty ? existingItems : items
        items = OwnerProfileOptimisticStore.upserting(post, into: baseline)
        hasLoaded = true
        detailCache.seed(posts: items)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))

        syncGeneration &+= 1
        let generation = syncGeneration
        #if DEBUG
        ProfilePostsSync.logPublishSucceeded(
            id: post.id.rawValue,
            visibleBefore: visibleBefore,
            optimisticAfter: items.count
        )
        ProfilePostsSync.logAuthoritativeRefreshStarted(generation: generation)
        ProfilePostsSync.logUIVisibleCount(items.count)
        #endif

        loadTask?.cancel()
        loadTask = Task { await performLoad(generation: generation) }
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        if awaitingScreenBootstrap {
            if items.isEmpty {
                state = .loading
            }
            return
        }
        syncGeneration &+= 1
        let generation = syncGeneration
        ProfileTabLoadProbe.loadStarted(.posts)
        loadTask = Task { await performLoad(generation: generation) }
    }

    func refresh() async {
        syncGeneration &+= 1
        let generation = syncGeneration
        loadTask?.cancel()
        await performLoad(generation: generation)
    }

    func loadMoreIfNeeded(currentPostID: PostID?) async {
        guard hasLoaded, nextCursor != nil, loadMoreTask == nil, !isLoadingMore else { return }
        guard let currentPostID, items.last?.id == currentPostID else { return }
        let cursor = nextCursor
        let generation = paginationGeneration
        isLoadingMore = true
        loadMoreTask = Task { @MainActor in
            defer {
                isLoadingMore = false
                loadMoreTask = nil
            }
            await performLoadMore(cursor: cursor, generation: generation)
        }
    }

    func openPost(_ post: Post) {
        detailCache.seed(post)
        navigationCoordinator.pushPostDetail(post.id)
    }

    func addPost() {
        navigationCoordinator.openCompose(.post)
    }

    func requestDelete(_ post: Post) {
        guard isOwner, deletingPostID == nil else { return }
        ExperienceHaptics.play(.warning)
        TradeDeleteConfirmationPresenter.scheduleConfirmation { [weak self] in
            self?.pendingDelete = post
        }
    }

    func isDeletingPost(_ id: PostID) -> Bool {
        deletingPostID == id
    }

    func confirmDelete(post explicitPost: Post? = nil) async {
        guard isOwner, deletingPostID == nil else { return }
        let post = explicitPost ?? pendingDelete
        guard let post else { return }
        pendingDelete = nil
        deletingPostID = post.id
        deleteErrorMessage = nil
        defer { deletingPostID = nil }
        let removedIndex = items.firstIndex { $0.id == post.id }
        items.removeAll { $0.id == post.id }
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        do {
            try await OwnerPostDeletionService.deleteOwnedPost(
                postID: post.id,
                owner: profileOwnerID,
                profiles: profiles,
                session: session,
                detailCache: detailCache
            )
            noteDeleteSucceeded(id: post.id)
            ExperienceHaptics.play(.success)
        } catch {
            if let removedIndex {
                items.insert(post, at: min(removedIndex, items.count))
            } else if !items.contains(where: { $0.id == post.id }) {
                items.append(post)
                items.sort { $0.createdAt > $1.createdAt }
            }
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            detailCache.seed(posts: items)
            deleteErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    private func performLoad(generation: UInt64) async {
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileOwnerID) {
            guard generation == syncGeneration else {
                #if DEBUG
                ProfilePostsSync.logStaleResponseDropped(
                    generation: generation,
                    currentGeneration: syncGeneration
                )
                #endif
                loadTask = nil
                return
            }
            hasLoaded = true
            let overlay = OwnerProfileOptimisticStore.shared.posts.filter {
                $0.authorProfileID == profileOwnerID
            }
            let serverMerged = OwnerProfileOptimisticStore.merging(
                overlay: overlay,
                into: profileOwnerID == DemoExperienceSupport.profileID
                    ? DemoGraph.posts(owner: profileOwnerID)
                    : ProfilePostFixtures.samples(owner: profileOwnerID)
            )
            items = OwnerProfileOptimisticStore.merging(overlay: serverMerged, into: items)
            detailCache.seed(posts: items)
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            #if DEBUG
            ProfilePostsSync.logAuthoritativeReturned(generation: generation, count: items.count)
            ProfilePostsSync.logUIVisibleCount(items.count)
            #endif
            OwnerProfileOptimisticStore.shared.syncOwnerPostsState(items)
            loadTask = nil
            return
        }

        state = items.isEmpty ? .loading : state
        paginationGeneration &+= 1
        initialLoadFailureGrace.cancel()
        // Wall pages use pinned and unpinned keysets. `rpc` stays for shell construction.
        _ = rpc
        do {
            let page = try await profiles.wallPosts(
                for: profileOwnerID,
                page: PageRequest(limit: ProfileTabBootstrapLoader.defaultPageSize)
            )
            let pageItems = page.items
            let cursor = page.nextCursor
            guard !Task.isCancelled else { return }
            guard generation == syncGeneration else {
                #if DEBUG
                ProfilePostsSync.logStaleResponseDropped(
                    generation: generation,
                    currentGeneration: syncGeneration
                )
                #endif
                loadTask = nil
                return
            }
            let overlay = OwnerProfileOptimisticStore.shared.posts.filter {
                $0.authorProfileID == profileOwnerID
            }
            let beforeCount = items.count
            let serverMerged = OwnerProfileOptimisticStore.merging(overlay: overlay, into: pageItems)
            items = excludingDeletedPosts(
                applyingServerPage(serverMerged, pageIsComplete: cursor == nil)
            )
            nextCursor = cursor
            detailCache.seed(posts: items)
            hasLoaded = true
            initialLoadFailureGrace.cancel()
            #if DEBUG
            ProfilePostsSync.logAuthoritativeReturned(generation: generation, count: pageItems.count)
            ProfilePostsSync.logReconciled(
                beforeCount: beforeCount,
                snapshotCount: pageItems.count,
                afterCount: items.count
            )
            ProfilePostsSync.logUIVisibleCount(items.count)
            #endif
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            OwnerProfileOptimisticStore.shared.syncOwnerPostsState(items)
            ProfileTabLoadProbe.loadCompleted(.posts, count: items.count)
            ProfileTabLoadProbe.state(.posts, loaded: hasLoaded, loading: state.isLoading, count: items.count)
        } catch {
            guard !Task.isCancelled else { return }
            guard generation == syncGeneration else {
                #if DEBUG
                ProfilePostsSync.logStaleResponseDropped(
                    generation: generation,
                    currentGeneration: syncGeneration
                )
                #endif
                loadTask = nil
                return
            }
            if items.isEmpty {
                if awaitingScreenBootstrap {
                    state = .loading
                } else {
                    let message = ProfileSectionSupport.message(for: error)
                    let failedGeneration = generation
                    initialLoadFailureGrace.scheduleIfNeeded(message: message) { [weak self] in
                        guard let self else { return false }
                        return !hasLoaded
                            && items.isEmpty
                            && syncGeneration == failedGeneration
                            && !awaitingScreenBootstrap
                    } present: { [weak self] message in
                        self?.state = .failed(message: message)
                    }
                }
            }
        }
        loadTask = nil
    }

    private func performLoadMore(cursor: String?, generation: Int) async {
        do {
            let page = try await profiles.wallPosts(
                for: profileOwnerID,
                page: PageRequest(cursor: cursor, limit: ProfileTabBootstrapLoader.defaultPageSize)
            )
            let newCursor = page.nextCursor
            guard generation == paginationGeneration, !Task.isCancelled else { return }
            if page.items.isEmpty {
                nextCursor = nil
                return
            }
            appendUniquePosts(page.items)
            nextCursor = newCursor
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: excludingDeletedPosts(page.items).map(\.id))
        } catch {
            guard generation == paginationGeneration else { return }
        }
    }

    /// A page much smaller than the list already on screen is not a delete.
    /// That was collapsing the profile to the one newest row.
    private func applyingServerPage(_ incoming: [Post], pageIsComplete: Bool) -> [Post] {
        sortedPosts(
            ProfileSectionSupport.applyingLoadedPage(
                incoming: incoming,
                loaded: items,
                orderedBy: \.createdAt,
                pageIsComplete: pageIsComplete
            )
        )
    }

    private func excludingDeletedPosts(_ posts: [Post]) -> [Post] {
        let deleted = OwnerProfileOptimisticStore.shared.deletedPostIDs
        guard !deleted.isEmpty else { return posts }
        return posts.filter { !deleted.contains($0.id) }
    }

    private func mergeIncomingPosts(_ incoming: [Post]) {
        guard !incoming.isEmpty else { return }
        let merged = ProfileSectionSupport.mergeKeepingExisting(
            incoming: incoming,
            loaded: items,
            orderedBy: \.createdAt
        )
        items = excludingDeletedPosts(sortedPosts(merged))
    }

    private func sortedPosts(_ posts: [Post]) -> [Post] {
        posts.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.rawValue > rhs.id.rawValue
        }
    }

    private func appendUniquePosts(_ pageItems: [Post]) {
        let existing = Set(items.map(\.id))
        let deleted = OwnerProfileOptimisticStore.shared.deletedPostIDs
        let fresh = pageItems.filter { !existing.contains($0.id) && !deleted.contains($0.id) }
        guard !fresh.isEmpty else {
            nextCursor = nil
            return
        }
        items.append(contentsOf: fresh)
        detailCache.seed(posts: items)
    }
}
