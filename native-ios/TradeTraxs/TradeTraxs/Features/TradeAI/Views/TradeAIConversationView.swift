import SwiftUI

/// Full-screen Trade AI thread (trade-scoped or portfolio).
struct TradeAIConversationView: View {
    @Bindable var viewModel: TradeAISectionViewModel
    let tradeID: TradeID
    var imagePipeline: (any ImagePipeline)?
    var onOpenTradeDetail: ((TradeID) -> Void)?

    @State private var scrollPosition: String?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    tradeContextCard

                    if viewModel.showsConversationStarters {
                        presetQuestions
                    }

                    if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                        ExperienceIndeterminateProgress()
                            .padding(.top, ExperienceSpacing.sm)
                    }

                    ForEach(viewModel.messages) { message in
                        TradeAIMessageCard(
                            message: message,
                            imagePipeline: imagePipeline,
                            showsTradeAttachments: false
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
        .navigationTitle("Trade AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.loadHistoryIfNeeded()
        }
    }

    @ViewBuilder
    private var tradeContextCard: some View {
        if let imagePipeline {
            let openDetail = onOpenTradeDetail
            Group {
                if let openDetail {
                    Button {
                        ExperienceHaptics.play(.selection)
                        openDetail(tradeID)
                    } label: {
                        tradeContextCardBody(imagePipeline: imagePipeline)
                    }
                    .buttonStyle(.experiencePlain)
                } else {
                    tradeContextCardBody(imagePipeline: imagePipeline)
                }
            }
            .accessibilityIdentifier("tradeAI.conversation.tradeContext")
        }
    }

    private func tradeContextCardBody(imagePipeline: any ImagePipeline) -> some View {
        SharedTradeMessageCard(
            trade: viewModel.trade,
            tradeID: tradeID,
            imagePipeline: imagePipeline,
            isOutgoing: false,
            includesBackground: true
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presetQuestions: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Suggested questions")
                .experienceStyle(.caption2, color: colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.35)
                .padding(.top, ExperienceSpacing.xs)

            ForEach(TradeAISuggestedPrompts.conversationStarters) { preset in
                Button {
                    Task { await viewModel.submitPreset(preset) }
                } label: {
                    Text(preset.title)
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
                .disabled(viewModel.isAnalyzing)
                .accessibilityIdentifier("tradeAI.conversation.preset.\(preset.id)")
            }
        }
    }

    private var composer: some View {
        AITradeCoachComposerBar(
            draft: $viewModel.draft,
            isLoading: viewModel.isAnalyzing,
            showsTradeAttach: false,
            stagedTrade: nil,
            pendingImageData: viewModel.pendingAttachmentData,
            imagePipeline: imagePipeline,
            onSend: { Task { await viewModel.send() } },
            onRemoveTrade: {},
            onRemoveImage: { viewModel.pendingAttachmentData = nil },
            onAttachTrade: {},
            onPickedImage: { data in
                viewModel.pendingAttachmentData = data
                viewModel.pendingAttachmentMime = "image/jpeg"
            }
        )
    }
}