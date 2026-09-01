import SwiftUI

struct ProfileOnboardingView: View {
    @State private var viewModel: ProfileOnboardingViewModel
    @Environment(\.themeColors) private var colors

    init(viewModel: ProfileOnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                header
                usernameField
                tradingStyleField
                traderTypeField
                startedTradingField
                bioField
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .experienceStyle(.footnote, color: colors.error)
                }
                ExperienceButton(
                    title: viewModel.isSubmitting ? "Saving…" : "Finish setup",
                    kind: .primary,
                    isEnabled: viewModel.canSubmit,
                    isLoading: viewModel.isSubmitting,
                    accessibilityIdentifier: "onboarding.submit"
                ) {
                    Task { await viewModel.submit() }
                }
            }
            .experiencePadding(.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .experienceScreenBackground()
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Let's get your account ready")
                .experienceStyle(.title2, color: colors.primaryText)
            Text("Choose a username and a few trading details to unlock TradeTraxs.")
                .experienceStyle(.body, color: colors.secondaryText)
            if !viewModel.displayName.isEmpty {
                Text("Signed in as \(viewModel.displayName)")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
        .padding(.top, ExperienceSpacing.xxl)
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Username")
                .experienceStyle(.footnote, color: colors.secondaryText)
            TextField("username", text: $viewModel.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.username)
                .onChange(of: viewModel.username) { _, newValue in
                    let sanitized = ProfileUsernamePolicy.sanitizeForTyping(newValue)
                    if sanitized != newValue {
                        viewModel.username = sanitized
                    }
                }
                .padding(ExperienceSpacing.md)
                .background(colors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            Text(ProfileUsernamePolicy.formatHint)
                .experienceStyle(.caption, color: colors.secondaryText)
        }
    }

    private var tradingStyleField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Trading style")
                .experienceStyle(.footnote, color: colors.secondaryText)
            TextField("e.g. Scalping, swing, investor…", text: $viewModel.tradingStyle)
                .padding(ExperienceSpacing.md)
                .background(colors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
        }
    }

    private var traderTypeField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Trader type")
                .experienceStyle(.footnote, color: colors.secondaryText)
            Picker("Trader type", selection: $viewModel.traderType) {
                Text("Select trader type").tag(Optional<TraderType>.none)
                ForEach([TraderType.futures, .options, .investor], id: \.self) { type in
                    Text(type.rawValue).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
        }
    }

    private var startedTradingField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Started trading")
                .experienceStyle(.footnote, color: colors.secondaryText)
            DatePicker(
                "Started trading",
                selection: startedTradingBinding,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(ExperienceSpacing.md)
            .background(colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Bio (optional)")
                .experienceStyle(.footnote, color: colors.secondaryText)
            TextField("Short bio", text: $viewModel.bio, axis: .vertical)
                .lineLimit(3...5)
                .padding(ExperienceSpacing.md)
                .background(colors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
        }
    }

    private var startedTradingBinding: Binding<Date> {
        Binding(
            get: {
                let formatter = DateFormatter()
                formatter.calendar = Calendar.current
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: viewModel.startedTrading) ?? Date()
            },
            set: { newDate in
                let formatter = DateFormatter()
                formatter.calendar = Calendar.current
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                viewModel.startedTrading = formatter.string(from: newDate)
            }
        )
    }
}
