import SwiftUI

enum RithmicConnectSheetMode: Equatable {
    case connect
    case importTrades
}

struct RithmicConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    let mode: RithmicConnectSheetMode
    let isBusy: Bool
    let systemChoices: [String]
    let prefilledUsername: String?
    let prefilledSystemName: String?
    let locksUsername: Bool
    let onSubmit: (_ username: String, _ password: String, _ systemName: String?) async -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var selectedSystem = ""
    @State private var isPasswordVisible = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    header
                    fieldsCard
                    securityNote
                    primaryAction
                }
                .experiencePadding(.xl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .experienceScreenBackground()
            .experienceNavigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clearSecrets()
                        dismiss()
                    }
                    .disabled(isBusy)
                }
            }
            .onAppear {
                applyPrefill()
            }
            .onDisappear {
                clearSecrets()
            }
        }
        .interactiveDismissDisabled(isBusy)
    }

    private var navigationTitle: String {
        switch mode {
        case .connect:
            return "Connect Rithmic"
        case .importTrades:
            return "Reconnect to Rithmic"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Rithmic")
                .font(ExperienceTypography.title2)
                .foregroundStyle(colors.primaryText)

            Text(subtitle)
                .experienceStyle(.body, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: String {
        switch mode {
        case .connect:
            return "Securely connect your Rithmic account to import your trading activity."
        case .importTrades:
            return "Sign in again to import new trades from your linked Rithmic account."
        }
    }

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            systemField

            if locksUsername, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text("Username")
                        .experienceStyle(.caption, color: colors.secondaryText)
                    Text(username)
                        .experienceStyle(.body, color: colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                        .background(colors.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
                }
                .accessibilityIdentifier("brokerIntegrations.rithmic.username")
            } else {
                AuthTextField(
                    title: "Username",
                    text: $username,
                    kind: .email,
                    textContentType: .username,
                    submitLabel: .next
                )
                .accessibilityIdentifier("brokerIntegrations.rithmic.username")
            }

            AuthTextField(
                title: "Password",
                text: $password,
                kind: .password,
                isSecureVisible: $isPasswordVisible,
                textContentType: .password,
                submitLabel: .done
            ) {
                submitIfValid()
            }
            .accessibilityIdentifier("brokerIntegrations.rithmic.password")
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .stroke(colors.border, lineWidth: ExperienceBorder.thin)
        }
        .allowsHitTesting(!isBusy)
        .opacity(isBusy ? ExperienceOpacity.disabled : ExperienceOpacity.opaque)
    }

    @ViewBuilder
    private var systemField: some View {
        let choices = effectiveSystemChoices
        if !choices.isEmpty {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Rithmic System")
                    .experienceStyle(.caption, color: colors.secondaryText)
                Picker("Rithmic System", selection: $selectedSystem) {
                    if choices.count > 1 {
                        Text("Select a system").tag("")
                    }
                    ForEach(choices, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ExperienceSpacing.md)
                .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                .background(colors.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            }
            .accessibilityIdentifier("brokerIntegrations.rithmic.system")
        } else if let prefilledSystemName,
                  !prefilledSystemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Rithmic System")
                    .experienceStyle(.caption, color: colors.secondaryText)
                Text(prefilledSystemName)
                    .experienceStyle(.body, color: colors.primaryText)
            }
        }
    }

    private var effectiveSystemChoices: [String] {
        if !systemChoices.isEmpty { return systemChoices }
        if let name = prefilledSystemName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            return [name]
        }
        return []
    }

    private var securityNote: some View {
        Text(securityCopy)
            .experienceStyle(.footnote, color: colors.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var securityCopy: String {
        switch mode {
        case .connect:
            return "Your Rithmic password is used only to establish this connection and is not saved by TradeTraxs."
        case .importTrades:
            return "TradeTraxs does not save your Rithmic password."
        }
    }

    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            ExperienceButton(
                title: primaryButtonLabel,
                kind: .primary,
                isEnabled: isBusy || localValidationOK,
                keepsEnabledAppearanceWhenDisabled: isBusy,
                isLoading: isBusy,
                accessibilityIdentifier: mode == .connect
                    ? "brokerIntegrations.rithmic.connect"
                    : "brokerIntegrations.rithmic.continueImport"
            ) {
                submitIfValid()
            }

            if isBusy {
                Text("Securely connecting to your broker. This may take a few seconds.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("brokerIntegrations.rithmic.connectingStatus")
            }
        }
    }

    private var primaryButtonLabel: String {
        if isBusy {
            return "Connecting to Rithmic..."
        }
        switch mode {
        case .connect:
            return "Connect Rithmic"
        case .importTrades:
            return "Continue Import"
        }
    }

    private var localValidationOK: Bool {
        let userOk = !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let passOk = !password.isEmpty
        let choices = effectiveSystemChoices
        if !choices.isEmpty {
            let system = selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines)
            if choices.count == 1 { return userOk && passOk }
            return userOk && passOk && !system.isEmpty
        }
        return userOk && passOk
    }

    private func applyPrefill() {
        if username.isEmpty,
           let prefill = prefilledUsername?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        {
            username = prefill
        }
        if selectedSystem.isEmpty {
            if let system = prefilledSystemName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                selectedSystem = system
            } else if let only = systemChoices.singleOrNil {
                selectedSystem = only
            }
        }
    }

    private func submitIfValid() {
        guard localValidationOK, !isBusy else { return }
        ExperienceKeyboard.dismiss()
        Task {
            let trimmedSelected = selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            let trimmedPrefilled = prefilledSystemName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            let system = trimmedSelected ?? trimmedPrefilled ?? systemChoices.singleOrNil
            await onSubmit(username, password, system)
        }
    }

    private func clearSecrets() {
        password = ""
        isPasswordVisible = false
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
