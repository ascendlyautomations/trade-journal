import SwiftUI
import UIKit

/// Dashboard → Trades — owner journal / trade history browser.
struct TradeHistoryView: View {
    @State private var viewModel: TradeHistoryViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: TradeHistoryViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                rpc: data.rpc
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    init(
        viewModel: TradeHistoryViewModel,
        imagePipeline: any ImagePipeline
    ) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if viewModel.items.isEmpty {
                    ExperienceListSkeleton(style: .tradeCard, rowCount: 4)
                } else {
                    listContent
                }
            case .failed(let message):
                if viewModel.items.isEmpty {
                    ExperienceErrorState(
                        title: "Couldn't load trades",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                } else {
                    listContent
                }
            case .loaded:
                if viewModel.isEmptyJournal {
                    ExperienceEmptyState(
                        icon: .trades,
                        title: "No trades yet",
                        message: "Log a trade to start building your journal.",
                        actionTitle: "Add Trade",
                        action: { viewModel.addTrade() }
                    )
                } else if viewModel.isEmptyFiltered {
                    ExperienceEmptyState(
                        icon: .search,
                        title: "No trades match these filters.",
                        message: nil,
                        actionTitle: "Clear Filters",
                        action: { viewModel.clearAllFilters() }
                    )
                } else {
                    listContent
                }
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Trades")
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search trades…"
        )
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.searchChanged()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.openFilters()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .overlay(alignment: .topTrailing) {
                            if viewModel.showsFilterIndicator {
                                Circle()
                                    .fill(colors.accent)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 4, y: -4)
                            }
                        }
                }
                .accessibilityLabel("Filters")
                .accessibilityIdentifier("trades.filters")
            }
        }
        .sheet(isPresented: $viewModel.showsFilterSheet) {
            TradeHistoryFilterSheet(viewModel: viewModel)
                .experienceSheetChrome()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            viewModel.handleJournalMutation()
        }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            viewModel.handleAccountMutation()
        }
        .confirmationDialog(
            "Delete this trade?",
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
            if let trade = viewModel.pendingDelete {
                Text("\(trade.symbol.ticker) will be removed from your journal.")
            }
        }
        .sheet(item: $viewModel.sharePayload) { payload in
            TradeHistoryShareSheet(items: [payload.text])
        }
        .accessibilityIdentifier("trades.home")
    }

    private var listContent: some View {
        List {
            Section {
                TradeHistoryFilterBar(viewModel: viewModel)
                    .listRowInsets(EdgeInsets(
                        top: ExperienceSpacing.sm,
                        leading: ExperienceSpacing.md,
                        bottom: ExperienceSpacing.xs,
                        trailing: ExperienceSpacing.md
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if !viewModel.activeChips.isEmpty {
                    chipStrip
                        .listRowInsets(EdgeInsets(
                            top: 0,
                            leading: ExperienceSpacing.md,
                            bottom: ExperienceSpacing.xs,
                            trailing: ExperienceSpacing.md
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if !viewModel.items.isEmpty {
                    summaryRow
                        .listRowInsets(EdgeInsets(
                            top: ExperienceSpacing.xs,
                            leading: ExperienceSpacing.md,
                            bottom: ExperienceSpacing.sm,
                            trailing: ExperienceSpacing.md
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            Section {
                ForEach(viewModel.items) { trade in
                    TradeJournalCard(
                        trade: trade,
                        accountName: viewModel.displayAccountTitle(for: trade.accountID),
                        imagePipeline: imagePipeline,
                        onOpen: { viewModel.openTrade(trade) },
                        onShare: { viewModel.shareTrade(trade) },
                        onEdit: { viewModel.editTrade(trade) },
                        onDelete: { viewModel.requestDelete(trade) }
                    )
                    .listRowInsets(EdgeInsets(
                        top: ExperienceSpacing.xs,
                        leading: ExperienceSpacing.md,
                        bottom: ExperienceSpacing.xs,
                        trailing: ExperienceSpacing.md
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.requestDelete(trade)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            viewModel.editTrade(trade)
                        } label: {
                            Label("Edit", systemImage: "square.and.pencil")
                        }
                        .tint(colors.accent)
                    }
                    .onAppear {
                        Task { await viewModel.loadMoreIfNeeded(currentTradeID: trade.id) }
                    }
                    .accessibilityIdentifier("trades.row.\(trade.id.rawValue)")
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if let message = viewModel.paginationErrorMessage {
                    Text(message)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var chipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.xs) {
                ForEach(viewModel.activeChips) { chip in
                    Button {
                        viewModel.removeChip(chip)
                    } label: {
                        HStack(spacing: 4) {
                            Text(chip.title)
                                .experienceStyle(.caption, color: colors.primaryText)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(colors.secondaryText)
                        }
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, 6)
                        .background(colors.fillSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(chip.title) filter")
                }
                if viewModel.showsClearAllChips {
                    Button {
                        viewModel.clearAllFilters()
                    } label: {
                        Text("Clear All")
                            .experienceStyle(.caption, color: colors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trades.clearAll")
                }
            }
        }
        .accessibilityIdentifier("trades.activeFilters")
    }

    private var summaryRow: some View {
        Text(viewModel.resultCountLabel)
            .experienceStyle(.footnote, color: colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("trades.summary")
    }
}

private struct TradeHistoryShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
