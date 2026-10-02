import SwiftUI

struct TradesContainerView: View {
    @Bindable var viewModel: TradesContainerViewModel
    let imagePipeline: any ImagePipeline
    @Bindable var engagementStore: EngagementStore
    @Bindable var vaultStore: VaultStore
    var profilePin: ProfilePinCallbacks? = nil
    var profilePinnedItems: [ProfilePinnedItem] = []

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        ProfileSectionContainerChrome(
            section: .trades,
            state: viewModel.state,
            emptyTitle: viewModel.emptyTitle,
            emptyMessage: viewModel.filter == .all && viewModel.showsOwnerActions
                ? nil
                : viewModel.emptyMessage,
            emptyActionTitle: viewModel.showsOwnerActions && viewModel.filter == .all
                ? "Add Trade"
                : nil,
            emptyAction: viewModel.showsOwnerActions && viewModel.filter == .all
                ? { viewModel.addTrade() }
                : nil,
            onRetry: { Task { await viewModel.refresh() } }
        ) {
            tradesContent
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            viewModel.handleJournalMutation()
        }
        .sheet(item: $viewModel.sharePayload) { payload in
            TradeShareSheet(items: [payload.text])
        }
        .confirmationDialog(
            "Delete Trade?",
            isPresented: Binding(
                get: { viewModel.pendingDelete != nil },
                set: { if !$0 { viewModel.pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Trade", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(
            "Couldn't delete trade",
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { if !$0 { viewModel.deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.deleteErrorMessage = nil }
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
        }
    }

    private var displayItems: [TradeSummary] {
        ProfilePinnedOrdering.displayItems(
            viewModel.visibleItems,
            profilePins: profilePinnedItems,
            contentType: .trade,
            contentID: { $0.id.rawValue }
        )
    }

    private func isProfilePinned(_ summary: TradeSummary) -> Bool {
        profilePinnedItems.contains {
            $0.contentType == .trade && $0.contentID == summary.id.rawValue
        }
    }

    @ViewBuilder
    private var tradesContent: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            ProfileTradesFilterBar(viewModel: viewModel)

            if let message = viewModel.filterEmptyMessage {
                Text(message)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .accessibilityIdentifier("profile.trades.filterEmpty")
            } else {
                LazyVStack(spacing: ExperienceSpacing.sm) {
                    ForEach(displayItems) { summary in
                        ProfileTradeCard(
                            summary: summary,
                            imagePipeline: imagePipeline,
                            engagementStore: engagementStore,
                            vaultStore: vaultStore,
                            showsOwnerActions: viewModel.showsOwnerActions,
                            onOpen: { viewModel.openTrade(summary) },
                            onShare: { viewModel.shareTrade(summary) },
                            onEdit: { viewModel.editTrade(summary) },
                            onDelete: viewModel.showsOwnerActions
                                ? {
                                    guard !viewModel.isDeletingTrade(summary.id) else { return }
                                    viewModel.requestDelete(summary)
                                }
                                : nil,
                            isDeleteInProgress: viewModel.isDeletingTrade(summary.id),
                            onReport: reportAction(for: summary),
                            profilePin: profilePin,
                            isProfilePinned: isProfilePinned(summary)
                        )
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .bottom))
                        )
                        .task {
                            await viewModel.loadMoreIfNeeded(currentTradeID: summary.id)
                        }
                    }
                }
                .animation(
                    ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                    value: displayItems.map(\.id)
                )
                .onChange(of: displayItems.map(\.id)) { _, ids in
                    viewModel.prefetchEngagement(for: ids)
                }
                .onAppear {
                    viewModel.prefetchEngagement(for: displayItems.map(\.id))
                }
                .accessibilityIdentifier("profile.trades.list")

                if viewModel.paginationErrorMessage != nil {
                    loadMoreFailure
                }
            }
        }
    }

    private var loadMoreFailure: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Couldn’t load more trades")
                .experienceStyle(.footnote, color: colors.secondaryText)
            Button {
                viewModel.retryLoadMore()
            } label: {
                Text("Try again")
                    .experienceStyle(.footnote, color: colors.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, ExperienceSpacing.xs)
        .accessibilityIdentifier("profile.trades.loadMoreError")
    }

    private func reportAction(for summary: TradeSummary) -> (() -> Void)? {
        guard !viewModel.showsOwnerActions else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            ContentReportSupport.presentTrade(
                summary.id,
                ownerID: viewModel.profileOwnerID,
                presenter: appEnvironment.contentReportPresenter
            )
        }
    }
}

private struct TradeShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
