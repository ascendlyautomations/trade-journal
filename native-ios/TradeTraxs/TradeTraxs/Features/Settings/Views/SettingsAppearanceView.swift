import SwiftUI

/// Apple Settings–style Appearance picker (System / TradeTraxs).
struct SettingsAppearanceView: View {
    @State private var viewModel: SettingsAppearanceViewModel

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment

    init(themeManager: ThemeManager) {
        _viewModel = State(initialValue: SettingsAppearanceViewModel(themeManager: themeManager))
    }

    init(viewModel: SettingsAppearanceViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                ForEach(viewModel.model.options) { option in
                    Button {
                        viewModel.select(option.id, reduceMotion: reduceMotion)
                    } label: {
                        HStack(spacing: ExperienceSpacing.sm) {
                            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                                Text(option.metadata.displayName)
                                    .experienceStyle(.body, color: colors.primaryText)
                                Text(option.metadata.detail)
                                    .experienceStyle(.footnote, color: colors.secondaryText)
                            }
                            Spacer(minLength: ExperienceSpacing.xs)
                            if option.isSelected {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(colors.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, ExperienceSpacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.metadata.displayName)
                    .accessibilityValue(option.isSelected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(option.isSelected ? [.isSelected, .isButton] : .isButton)
                    .accessibilityIdentifier("settings.appearance.\(option.id.rawValue)")
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("System matches Light and Dark with iOS. TradeTraxs uses our brand colors.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Appearance")
        .onAppear { viewModel.refresh() }
        .onChange(of: appEnvironment.themeManager.selectedIdentifier) { _, _ in
            viewModel.refresh()
        }
        .accessibilityIdentifier("settings.appearance")
    }
}
