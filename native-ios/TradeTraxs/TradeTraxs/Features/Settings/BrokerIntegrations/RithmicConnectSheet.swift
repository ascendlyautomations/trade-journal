import SwiftUI

struct RithmicConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    let isBusy: Bool
    let systemChoices: [String]
    let reconnectTitle: String
    let onSubmit: (_ username: String, _ password: String, _ systemName: String?) async -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var selectedSystem = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(reconnectTitle)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }

                Section("Rithmic Login") {
                    TextField("Rithmic Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("brokerIntegrations.rithmic.username")

                    SecureField("Rithmic Password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("brokerIntegrations.rithmic.password")
                }

                if !systemChoices.isEmpty {
                    Section("Rithmic System") {
                        Picker("System", selection: $selectedSystem) {
                            Text("Select a system").tag("")
                            ForEach(systemChoices, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }
            }
            .experienceNavigationTitle("Connect Rithmic")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clearSecrets()
                        dismiss()
                    }
                    .disabled(isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        Task {
                            let system = selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                                ?? systemChoices.singleOrNil
                            await onSubmit(username, password, system)
                        }
                    }
                    .disabled(isBusy || !canSubmit)
                }
            }
            .onAppear {
                if selectedSystem.isEmpty, let only = systemChoices.singleOrNil {
                    selectedSystem = only
                }
            }
            .onDisappear {
                clearSecrets()
            }
        }
    }

    private var canSubmit: Bool {
        let userOk = !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let passOk = !password.isEmpty
        if !systemChoices.isEmpty {
            let system = selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines)
            return userOk && passOk && !system.isEmpty
        }
        return userOk && passOk
    }

    private func clearSecrets() {
        password = ""
    }
}

private extension Array where Element == String {
    var singleOrNil: String? {
        count == 1 ? first : nil
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
