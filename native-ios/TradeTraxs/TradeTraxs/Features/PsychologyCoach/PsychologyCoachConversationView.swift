import SwiftUI

/// Full-screen Psychology Coach thread — layout parity with ``TradeAIConversationView``.
struct PsychologyCoachConversationView: View {
    let messages: [AICoachConversationMessage]
    let isLoading: Bool
    let isLoadingBootstrap: Bool
    @Binding var draft: String
    let onSend: () -> Void

    @State private var messageScrollAnchorID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    if isLoadingBootstrap && messages.isEmpty {
                        ExperienceIndeterminateProgress()
                            .padding(.top, ExperienceSpacing.sm)
                    }

                    ForEach(messages) { message in
                        AICoachMessageCard(
                            role: message.role,
                            content: message.content,
                            assistantTitle: "Psychology Coach"
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aiCoachConversationMessageScroll()
            .scrollPosition(id: $messageScrollAnchorID, anchor: .bottom)
            .onChange(of: messages.count) { _, count in
                guard count > 0 else { return }
                messageScrollAnchorID = messages.last?.id
            }

            composer
        }
        .aiCoachConversationRootChrome()
        .toolbar(.hidden, for: .tabBar)
    }

    private var composer: some View {
        AITradeCoachComposerBar(
            draft: $draft,
            isLoading: isLoading,
            showsTradeAttach: false,
            stagedTrade: nil,
            pendingImageData: nil,
            imagePipeline: nil,
            onSend: onSend,
            onRemoveTrade: {},
            onRemoveImage: {},
            onAttachTrade: {},
            onPickedImage: { _ in }
        )
    }
}