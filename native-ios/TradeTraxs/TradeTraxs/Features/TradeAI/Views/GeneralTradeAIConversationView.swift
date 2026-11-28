import SwiftUI

/// Full-screen General Trade AI thread — layout parity with ``TradeAIConversationView``.
struct GeneralTradeAIConversationView: View {
    @Bindable var viewModel: GeneralTradeAICoachViewModel
    let imagePipeline: (any ImagePipeline)?
    let navigationCoordinator: NavigationCoordinator

    @State private var scrollPosition: String?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    scopeContextHeader

                    if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                        ExperienceIndeterminateProgress()
                            .padding(.top, ExperienceSpacing.sm)
                    }

                    ForEach(viewModel.messages) { message in
                        TradeAIMessageCard(
                            message: message,
                            imagePipeline: imagePipeline,
                            tradeForAttachment: { viewModel.tradeForAttachment($0) },
                            onOpenTrade: { tradeID in
                                navigationCoordinator.pushHome(.tradeDetail(tradeID))
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
            }
            .scrollPosition(id: $scrollPosition, anchor: .bottom)
            .onChange(of: viewModel.messages.count) { _, count in
                guard count > 0 else { return }
                scrollPosition = viewModel.messages.last?.id
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .experienceStyle(.caption, color: colors.error)
                    .padding(.horizontal, ExperienceSpacing.md)
            }

            if let persistError = viewModel.persistErrorMessage {
                HStack {
                    Text(persistError)
                        .experienceStyle(.caption, color: colors.secondaryText)
                    Spacer()
                    Button("Retry Save") {
                        Task { await viewModel.retryPersistIfNeeded() }
                    }
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .foregroundStyle(colors.accent)
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.bottom, ExperienceSpacing.xs)
            }

            composer
        }
        .experienceScreenBackground()
        .toolbar(.hidden, for: .tabBar)
    }

    private var scopeContextHeader: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            TradingRulesAnalyticsFilterBar(
                scope: viewModel.scopeController,
                onManageAccounts: {
                    navigationCoordinator.pushHome(.settings(.tradingAccounts))
                },
                onFiltersTap: {
                    viewModel.scopeController.prepareDraftScopeFilters()
                    viewModel.scopeController.showsFiltersSheet = true
                }
            )
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            colors.fillSecondary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
        .accessibilityIdentifier("generalTradeAI.scopeFilters")
    }

    private var composer: some View {
        AITradeCoachComposerBar(
            draft: $viewModel.draft,
            isLoading: viewModel.isLoading,
            showsTradeAttach: true,
            stagedTrade: viewModel.pendingSharedTrade,
            pendingImageData: viewModel.pendingAttachmentData,
            imagePipeline: imagePipeline,
            onSend: { Task { await viewModel.send() } },
            onRemoveTrade: { viewModel.pendingSharedTrade = nil },
            onRemoveImage: { viewModel.pendingAttachmentData = nil },
            onAttachTrade: { viewModel.presentTradePicker() },
            onPickedImage: { data in
                viewModel.pendingAttachmentData = data
                viewModel.pendingAttachmentMime = "image/jpeg"
            }
        )
    }
}