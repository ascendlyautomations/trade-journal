import SwiftUI

@Observable
@MainActor
final class ContentDraftsListModel {
    private(set) var drafts: [ContentDraft] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let repository: any ContentDraftRepository
    private var hasLoaded = false

    init(repository: any ContentDraftRepository) {
        self.repository = repository
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await reload() }
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await repository.listDrafts()
            drafts = loaded.sorted { $0.updatedAt > $1.updatedAt }
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func delete(_ draft: ContentDraft) async {
        drafts.removeAll { $0.id == draft.id }
        do {
            try await repository.deleteDraft(id: draft.id)
        } catch {
            errorMessage = UserFacingError.message(for: error)
            await reload()
        }
    }
}

struct ContentDraftsListView: View {
    @State private var model: ContentDraftsListModel
    let onOpen: (ContentDraft) -> Void

    @Environment(\.themeColors) private var colors

    init(repository: any ContentDraftRepository, onOpen: @escaping (ContentDraft) -> Void) {
        _model = State(initialValue: ContentDraftsListModel(repository: repository))
        self.onOpen = onOpen
    }

    var body: some View {
        Group {
            if let errorMessage = model.errorMessage, model.drafts.isEmpty {
                ExperienceErrorState(
                    title: "Couldn't load drafts",
                    message: errorMessage,
                    onRetry: { Task { await model.reload() } }
                )
            } else if model.drafts.isEmpty && !model.isLoading {
                ExperienceEmptyState(
                    title: "No drafts",
                    message: "Saved trades, posts, achievements, and stories show up here.",
                    accessibilityIdentifier: "contentDrafts.empty"
                )
            } else {
                List {
                    ForEach(model.drafts) { draft in
                        Button {
                            onOpen(draft)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.listTitle)
                                    .experienceStyle(.body, color: colors.primaryText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(draft.updatedLabel)
                                    .experienceStyle(.caption, color: colors.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, ExperienceSpacing.xxs)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("contentDrafts.row.\(draft.id.uuidString)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await model.delete(draft) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .experienceInsetGroupedListStyle(pageBackground: true)
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Drafts")
        .overlay {
            if model.isLoading && model.drafts.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await model.reload() }
        .task { model.loadIfNeeded() }
        .accessibilityIdentifier("contentDrafts.list")
    }
}
