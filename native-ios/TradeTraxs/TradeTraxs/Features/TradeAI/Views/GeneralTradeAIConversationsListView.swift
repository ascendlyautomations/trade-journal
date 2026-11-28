import SwiftUI

/// Full list of General Trade AI conversations (`AI Conversations`).
struct GeneralTradeAIConversationsListView: View {
    @Bindable var viewModel: GeneralTradeAICoachViewModel

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    var body: some View {
        List {
            if viewModel.sortedGeneralConversations.isEmpty {
                Text("No conversations yet.")
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.sortedGeneralConversations) { item in
                    HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                        if isEditing {
                            Button {
                                viewModel.presentRename(for: item)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(colors.secondaryText)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.experiencePlain)
                        }

                        Button {
                            guard !isEditing else { return }
                            Task {
                                await viewModel.selectConversation(item.id)
                                dismiss()
                            }
                        } label: {
                            rowContent(item)
                        }
                        .buttonStyle(.experiencePlain)
                        .disabled(isEditing)
                    }
                    .listRowBackground(colors.fillSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .experiencePlainListStyle()
        .experienceScreenBackground()
        .experienceNavigationTitle("AI Conversations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    ExperienceHaptics.play(.selection)
                    isEditing.toggle()
                }
                .font(.body.weight(isEditing ? .semibold : .regular))
                .foregroundStyle(colors.accent)
            }
        }
        .sheet(isPresented: $viewModel.showsRenameSheet) {
            AICoachRenameConversationSheet(
                title: $viewModel.renameDraft,
                isSaveDisabled: viewModel.renameDraft
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onCancel: {
                    viewModel.showsRenameSheet = false
                    viewModel.renameTargetID = nil
                },
                onSave: { Task { await viewModel.submitRename() } }
            )
        }
        .accessibilityIdentifier("generalTradeAI.conversationsList")
    }

    private func rowContent(_ item: TradeAIConversationInboxItem) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                Text(item.title ?? "General Trade AI")
                    .experienceStyle(.body, color: colors.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let timestamp = item.lastMessageAt {
                    Text(MessagesInboxSupport.relativeTimestamp(timestamp))
                        .experienceStyle(.caption, color: colors.tertiaryText)
                        .lineLimit(1)
                }
            }
            if let preview = item.preview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                Text(preview)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ExperienceSpacing.xxs)
    }
}