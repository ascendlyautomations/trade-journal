import SwiftUI

/// Themed rename sheet for AI coach conversations.
struct AICoachRenameConversationSheet: View {
    @Binding var title: String
    var isSaveDisabled: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    @Environment(\.themeColors) private var colors
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SettingsLabeledField(title: "Conversation name") {
                        TextField("Conversation name", text: $title)
                            .textInputAutocapitalization(.sentences)
                            .focused($titleFocused)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .experienceTradeTraxsFormStyle(pageBackground: false)
            .experienceNavigationTitle("Rename Conversation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(isSaveDisabled)
                }
            }
        }
        .experienceSheetChrome(
            detents: [.height(252)],
            dragIndicator: .visible
        )
        .onAppear { titleFocused = true }
        .accessibilityIdentifier("aiCoach.renameConversation.sheet")
    }
}