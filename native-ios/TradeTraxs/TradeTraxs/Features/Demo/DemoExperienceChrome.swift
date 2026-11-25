import SwiftUI

struct GuestModeLeaveButton: View {
    @Environment(\.themeColors) private var colors
    @Bindable private var launchController = AppLaunchController.shared

    var body: some View {
        Button {
            ExperienceHaptics.play(.selection)
            launchController.exitDemoExplore()
        } label: {
            Text("Exit Guest Mode")
                .font(ExperienceTypography.footnote.weight(.semibold))
                .foregroundStyle(colors.accent)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.xs)
                .background(colors.surfacePrimary, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(colors.border.opacity(0.8), lineWidth: ExperienceBorder.hairline)
                }
                .experienceTouchTarget()
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Exit Guest Mode")
        .accessibilityHint("Returns to sign in")
        .accessibilityIdentifier("guest.leave")
    }
}

/// Centers the Exit Guest Mode control just above the tab bar.
struct GuestModeLeaveButtonPlacement: View {
    var body: some View {
        GuestModeLeaveButton()
            .padding(.top, ExperienceSpacing.xxs)
            .padding(.bottom, ExperienceSpacing.sm)
            .frame(maxWidth: .infinity)
    }
}

struct GuestModeShellModifier: ViewModifier {
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
        modifier(GuestModeShellModifier())
    }
}

typealias DemoExperienceLeaveButton = GuestModeLeaveButton
typealias DemoExperienceLeaveButtonPlacement = GuestModeLeaveButtonPlacement
