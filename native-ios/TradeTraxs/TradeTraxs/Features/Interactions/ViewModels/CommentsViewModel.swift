import Foundation
import Observation

@Observable
@MainActor
final class CommentsViewModel {
    private(set) var comments: [InteractionComment] = []
    private(set) var isLoading = false
    private(set) var isPosting = false
    private(set) var errorMessage: String?
    var sort: CommentSortOrder = .oldest
    var draft = ""

    let target: InteractionTarget

    private let repository: any InteractionRepository
    private let engagementStore: EngagementStore
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache?
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    init(
        target: InteractionTarget,
        repository: any InteractionRepository,
        engagementStore: EngagementStore,
        session: any SessionProviding,
        detailCache: DetailPresentationCache? = nil
    ) {
        self.target = target
        self.repository = repository
        self.engagementStore = engagementStore
        self.session = session
        self.detailCache = detailCache
    }

    var topLevelComments: [InteractionComment] {
        comments.filter { !$0.isReply }
    }

    func replies(to parentID: CommentID) -> [InteractionComment] {
        comments.filter { $0.parentCommentID == parentID }
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        loadTask = Task { await refresh() }
    }

    func refresh() async {
        isLoading = comments.isEmpty
        errorMessage = nil
        do {
            if target.id.hasPrefix("dev-") {
                comments = []
                hasLoaded = true
                // Keep any seeded/list-cached count — fixtures have no remote comments table.
            } else {
                let loaded = try await repository.comments(for: target, order: sort)
                guard !Task.isCancelled else { return }
                comments = loaded
                hasLoaded = true
                engagementStore.replaceCommentCount(loaded.count, on: target)
            }
        } catch {
            errorMessage = ProfileSectionSupport.message(for: error)
        }
        isLoading = false
        loadTask = nil
    }

    func setSort(_ order: CommentSortOrder) {
        guard sort != order else { return }
        sort = order
        ExperienceHaptics.play(.selection)
        Task { await refresh() }
    }

    func submit() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isPosting else { return }
        isPosting = true
        defer { isPosting = false }

        let userID = await session.currentUserID.map { ProfileID($0.rawValue) }
            ?? ProfileID("dev.local")
        // Reuse already-cached viewer profile for optimistic avatar — no network.
        let cachedViewer = detailCache?.profile(id: userID)
        let optimisticID = CommentID("local-\(UUID().uuidString)")
        let optimistic = InteractionComment(
            id: optimisticID,
            target: target,
            authorProfileID: userID,
            authorUsername: cachedViewer?.username,
            authorDisplayName: cachedViewer?.displayName,
            authorAvatarURL: cachedViewer?.avatar?.id,
            body: text,
            parentCommentID: nil,
            createdAt: Date(),
            isPinned: false
        )
        let previous = comments
        insertSorted(optimistic)
        draft = ""
        engagementStore.applyCommentCountDelta(1, on: target)
        ExperienceHaptics.play(.selection)

        if target.id.hasPrefix("dev-") {
            ExperienceHaptics.play(.success)
            return
        }

        do {
            let created = try await repository.addComment(body: text, parentID: nil, on: target)
            if let index = comments.firstIndex(where: { $0.id == optimisticID }) {
                comments[index] = created
            } else {
                insertSorted(created)
            }
            ExperienceHaptics.play(.success)
        } catch {
            comments = previous
            engagementStore.applyCommentCountDelta(-1, on: target)
            draft = text
            errorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    /// Architecture-ready — edit UI ships when web exposes body update.
    func beginEdit(_: InteractionComment) {
        // Reserved for Phase 6 follow-up (web pin-only today).
    }

    private func insertSorted(_ comment: InteractionComment) {
        comments.append(comment)
        if sort == .newest {
            comments.sort { $0.createdAt > $1.createdAt }
        } else {
            comments.sort { $0.createdAt < $1.createdAt }
        }
    }

    func delete(_ comment: InteractionComment) async {
        let previous = comments
        let removedIDs = Set(
            comments
                .filter { $0.id == comment.id || $0.parentCommentID == comment.id }
                .map(\.id)
        )
        comments.removeAll { removedIDs.contains($0.id) }
        engagementStore.applyCommentCountDelta(-removedIDs.count, on: target)

        if target.id.hasPrefix("dev-") {
            ExperienceHaptics.play(.success)
            return
        }

        do {
            try await repository.deleteComment(id: comment.id, on: target)
            ExperienceHaptics.play(.success)
        } catch {
            comments = previous
            engagementStore.replaceCommentCount(previous.count, on: target)
            errorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }
}
