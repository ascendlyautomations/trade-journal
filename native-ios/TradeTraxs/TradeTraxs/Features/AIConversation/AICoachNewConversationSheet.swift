import SwiftUI

/// Compact themed sheet for naming a new AI coach conversation (General Trade AI, etc.).
struct AICoachNewConversationSheet: View {
    let scopeDescription: String
    @Binding var title: String
    var isCreateDisabled: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void

    @Environment(\.themeColors) private var colors
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SettingsLabeledField(title: "Conversation name") {
                        TextField("e.g. Weekly review", text: $title)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
                            .focused($titleFocused)
                    }
                } footer: {
                    Text(scopeDescription)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .scrollContentBackground(.hidden)
            .experienceTradeTraxsFormStyle(pageBackground: false)
            .experienceNavigationTitle("New Conversation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: onCreate)
                        .disabled(isCreateDisabled)
                }
            }
        }
        .experienceSheetChrome(
            detents: [.height(272)],
            dragIndicator: .visible,
            interactiveDismiss: true
        )
        .onAppear { titleFocused = true }
        .accessibilityIdentifier("aiCoach.newConversation.sheet")
    }
}