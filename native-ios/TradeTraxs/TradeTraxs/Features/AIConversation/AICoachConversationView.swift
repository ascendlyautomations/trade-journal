import SwiftUI

/// Shared scroll + composer chrome for Psychology Coach and other AI coach threads.
struct AICoachConversationView: View {
  var navigationTitle: String
    var assistantTitle: String
    var disclaimer: String?
    var messages: [AICoachConversationMessage]
    var isLoading: Bool
    var draft: Binding<String>
    var sendTitle: String = "Send"
    var isSendEnabled: Bool
    var onSend: () -> Void

    @Environment(\.themeColors) private var colors
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                        if let disclaimer {
                            Text(disclaimer)
                                .experienceStyle(.footnote, color: colors.tertiaryText)
                        }

                        ForEach(messages) { message in
                            AICoachMessageCard(
                                role: message.role,
                                content: message.content,
                                assistantTitle: assistantTitle
                            )
                            .id(message.id)
                        }

                        if isLoading {
                            ExperienceIndeterminateProgress()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, ExperienceSpacing.sm)
                        }
                    }
                    .padding(ExperienceSpacing.md)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isLoading) { _, loading in
                    if !loading { scrollToBottom(proxy: proxy) }
                }
            }

            composer
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(navigationTitle)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: ExperienceSpacing.sm) {
            TextField("Ask a follow-up…", text: draft, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.plain)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, 10)
                .background(colors.fillSecondary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                .focused($composerFocused)
                .disabled(isLoading)

            Button(sendTitle) {
                composerFocused = false
                onSend()
            }
            .font(.system(.subheadline, design: .default).weight(.semibold))
            .foregroundStyle(isSendEnabled ? colors.accent : colors.tertiaryText)
            .disabled(!isSendEnabled || isLoading)
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}