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
    @State private var pendingDelete: ContentDraft?
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
                        ContentDraftListRow(
                            draft: draft,
                            onOpen: { onOpen(draft) },
                            onDelete: { pendingDelete = draft }
                        )
                        .accessibilityIdentifier("contentDrafts.row.\(draft.id.uuidString)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = draft
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
        .confirmationDialog(
            "Delete draft?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Draft", role: .destructive) {
                guard let draft = pendingDelete else { return }
                pendingDelete = nil
                Task { await model.delete(draft) }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This draft will be permanently deleted.")
        }
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

private struct ContentDraftListRow: View {
    let draft: ContentDraft
    let onOpen: () -> Void
    let onDelete: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.listTitle)
                        .experienceStyle(.body, color: colors.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(draft.updatedLabel)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: ExperienceSpacing.md) {
                Button("Edit", action: onOpen)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(colors.primaryText)
                    .accessibilityIdentifier("contentDrafts.edit.\(draft.id.uuidString)")

                Button("Delete", role: .destructive, action: onDelete)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("contentDrafts.delete.\(draft.id.uuidString)")
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .experienceDashboardListRow()
    }
}
