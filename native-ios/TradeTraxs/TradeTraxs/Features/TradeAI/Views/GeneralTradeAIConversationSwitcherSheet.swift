import SwiftUI

/// Compact conversation picker for General Trade AI (max 6 + See More).
struct GeneralTradeAIConversationSwitcherSheet: View {
    @Bindable var viewModel: GeneralTradeAICoachViewModel
    let onSeeMore: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.dropdownConversations) { item in
                        conversationRow(item)
                            .listRowBackground(colors.fillSecondary)
                    }
                }

                Section {
                    Button {
                        dismiss()
                        viewModel.showsNewConversationSheet = true
                    } label: {
                        Label("New Conversation", systemImage: "plus.bubble")
                            .experienceStyle(.body, color: colors.accent)
                    }
                    .listRowBackground(colors.fillSecondary)

                    if viewModel.hasMoreConversationsThanDropdown {
                        Button {
                            dismiss()
                            onSeeMore()
                        } label: {
                            Text("See More")
                                .experienceStyle(.body, color: colors.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .listRowBackground(colors.fillSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .experiencePlainListStyle()
            .experienceScreenBackground()
            .experienceNavigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .experienceSheetChrome(
            detents: viewModel.hasMoreConversationsThanDropdown ? [.height(420), .medium] : [.height(360)],
            dragIndicator: .visible
        )
    }

    private func conversationRow(_ item: TradeAIConversationInboxItem) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Button {
                viewModel.presentRename(for: item)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
                    .frame(width: ExperienceAccessibility.minTouchTarget, height: ExperienceAccessibility.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Rename \(item.title ?? "conversation")")

            Button {
                Task {
                    await viewModel.selectConversation(item.id)
                    dismiss()
                }
            } label: {
                HStack(spacing: ExperienceSpacing.xs) {
                    Text(item.title ?? "General Trade AI")
                        .experienceStyle(.body, color: colors.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if viewModel.conversationID == item.id {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
            }
            .buttonStyle(.experiencePlain)
        }
        .accessibilityElement(children: .combine)
    }
}