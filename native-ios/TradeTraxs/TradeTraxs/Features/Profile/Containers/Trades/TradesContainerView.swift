import SwiftUI

struct TradesContainerView: View {
    @Bindable var viewModel: TradesContainerViewModel
    let imagePipeline: any ImagePipeline
    @Bindable var engagementStore: EngagementStore

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            ProfileTradesFilterBar(viewModel: viewModel)
                .experiencePadding(.horizontal, .lg)

            if let paginationErrorMessage = viewModel.paginationErrorMessage {
                ExperienceBanner(
                    title: "Couldn’t load more trades",
                    message: paginationErrorMessage,
                    tone: .warning
                )
                .experiencePadding(.horizontal, .lg)
            }

            ProfileSectionContainerChrome(
                section: .trades,
                state: viewModel.state,
                emptyTitle: viewModel.emptyTitle,
                emptyMessage: viewModel.emptyMessage,
                emptyActionTitle: viewModel.showsOwnerActions && viewModel.filter == .all
                    ? "Add Trade"
                    : nil,
                emptyAction: viewModel.showsOwnerActions && viewModel.filter == .all
                    ? { viewModel.addTrade() }
                    : nil,
                onRetry: { Task { await viewModel.refresh() } }
            ) {
                LazyVStack(spacing: ExperienceSpacing.sm) {
                    ForEach(viewModel.visibleItems) { trade in
                        ProfileTradeCard(
                            trade: trade,
                            accountName: viewModel.accountName(for: trade),
                            imagePipeline: imagePipeline,
                            engagementStore: engagementStore,
                            showsOwnerActions: viewModel.showsOwnerActions,
                            onOpen: { viewModel.openTrade(trade) },
                            onShare: { viewModel.shareTrade(trade) },
                            onEdit: { viewModel.editTrade(trade) },
                            onDelete: { viewModel.requestDelete(trade) }
                        )
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .bottom))
                        )
                        .task {
                            await viewModel.loadMoreIfNeeded(currentTradeID: trade.id)
                        }
                    }
                }
                .animation(
                    ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                    value: viewModel.visibleItems.map(\.id)
                )
                .onChange(of: viewModel.visibleItems.map(\.id)) { _, ids in
                    viewModel.prefetchEngagement(for: ids)
                }
                .onAppear {
                    viewModel.prefetchEngagement(for: viewModel.visibleItems.map(\.id))
                }
            }
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
    }
}

private struct TradeShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
