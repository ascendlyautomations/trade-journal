import SwiftUI

struct DemoExperienceLeaveButton: View {
    @Environment(\.themeColors) private var colors
    @Bindable private var launchController = AppLaunchController.shared

    var body: some View {
        Button {
            ExperienceHaptics.play(.selection)
            launchController.exitDemoExplore()
        } label: {
            Text("Leave Demo")
                .font(ExperienceTypography.footnote.weight(.semibold))
                .foregroundStyle(colors.accent)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.xs)
                .background(colors.surfacePrimary, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(colors.border.opacity(0.8), lineWidth: ExperienceBorder.hairline)
                }
        }
        .buttonStyle(.plain)
        .experienceTouchTarget()
        .accessibilityLabel("Leave Demo")
        .accessibilityHint("Returns to sign in")
        .accessibilityIdentifier("demo.leave")
    }
}

/// Centers the existing Leave Demo control just above the tab bar.
struct DemoExperienceLeaveButtonPlacement: View {
    var body: some View {
        DemoExperienceLeaveButton()
            .padding(.top, ExperienceSpacing.xxs)
            .padding(.bottom, ExperienceSpacing.sm)
            .frame(maxWidth: .infinity)
    }
}

struct DemoExperienceShellModifier: ViewModifier {
    @Bindable private var launchController = AppLaunchController.shared

    func body(content: Content) -> some View {
        content
            .demoModeAuthGate()
            .exploreModeConversionPrompt()
            .onChange(of: launchController.environment.navigation.store.presentedFullScreen) { _, cover in
                guard let cover else { return }
                if DemoProtectedNavigation.interceptIfNeeded(.fullScreen(cover)) {
                    launchController.environment.navigation.coordinator.dismissFullScreen()
                }
            }
            .onChange(of: launchController.environment.navigation.store.presentedSheet) { _, sheet in
                guard let sheet else { return }
                if DemoProtectedNavigation.interceptIfNeeded(.sheet(sheet)) {
                    launchController.environment.navigation.coordinator.dismissSheet()
                }
            }
    }
}

extension View {
    func demoExperienceShellChrome() -> some View {
        modifier(DemoExperienceShellModifier())
    }
}
