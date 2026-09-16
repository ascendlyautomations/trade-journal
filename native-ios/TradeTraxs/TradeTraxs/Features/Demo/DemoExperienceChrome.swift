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
                .font(ExperienceTypography.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xxs)
                .background(colors.fillSecondary.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
        .experienceTouchTarget()
        .accessibilityLabel("Leave Demo")
        .accessibilityHint("Returns to sign in")
        .accessibilityIdentifier("demo.leave")
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
