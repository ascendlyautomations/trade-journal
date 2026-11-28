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
                    if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                        ExperienceIndeterminateProgress()
                            .padding(.top, ExperienceSpacing.sm)
                    }

                    if viewModel.showsConversationStarters {
                        emptyStateIntro
                        suggestedQuestions
                    }

                    ForEach(viewModel.messages) { message in
                        TradeAIMessageCard(
                            message: message,
                            imagePipeline: imagePipeline,
                            tradeForAttachment: { viewModel.tradeForAttachment($0) },
                            onOpenTrade: { tradeID in
                                navigationCoordinator.pushHome(.tradeDetail(tradeID))
                            },
                            renderingMode: .preferMarkdown
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aiCoachConversationMessageScroll()
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
        .aiCoachConversationRootChrome()
        .safeAreaInset(edge: .top, spacing: 0) {
            pinnedScopeFilterBar
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var pinnedScopeFilterBar: some View {
        ExperiencePinnedAnalyticsFilterBar {
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
        .accessibilityIdentifier("generalTradeAI.scopeFilters")
    }

    private var emptyStateIntro: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(GeneralTradeAISuggestedQuestions.introTitle)
                .experienceStyle(.headline, color: colors.primaryText)
            Text(GeneralTradeAISuggestedQuestions.introBody)
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, ExperienceSpacing.sm)
        .accessibilityIdentifier("generalTradeAI.emptyState.intro")
    }

    private var suggestedQuestions: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Suggested questions")
                .experienceStyle(.caption2, color: colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.35)
                .padding(.top, ExperienceSpacing.xs)

            ForEach(Array(GeneralTradeAISuggestedQuestions.starters.enumerated()), id: \.offset) { index, question in
                Button {
                    Task { await viewModel.submitSuggestedQuestion(question) }
                } label: {
                    Text(question)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.vertical, 10)
                        .background(
                            colors.fillSecondary,
                            in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        )
                }
                .buttonStyle(.experiencePlain)
                .disabled(viewModel.isLoading)
                .accessibilityIdentifier("generalTradeAI.starter.\(index)")
            }
        }
        .accessibilityIdentifier("generalTradeAI.suggestedQuestions")
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