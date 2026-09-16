import SwiftUI

/// TEST configuration — conversion prompts after Explore Mode dwell time.
enum ExploreModeConversionPrompt {
    /// Cumulative seconds from Explore entry for each prompt (2m, 3.5m, 5m, 10m).
    static let presentationOffsetsSeconds: [TimeInterval] = [
        2 * 60,
        3.5 * 60,
        5 * 60,
        10 * 60,
    ]

    static let title = "Enjoying TradeTraxs?"
    static let message =
        "Would you like to create an account to unlock the full TradeTraxs experience?"

    static let createAccountTitle = "Create Account"
    static let keepExploringTitle = "Keep Exploring"
    static let signInTitle = "Sign In"
}

@Observable
@MainActor
final class ExploreModeConversionPromptCoordinator {
    static let shared = ExploreModeConversionPromptCoordinator()

    private(set) var isPresented = false
    private var timerTask: Task<Void, Never>?

    private init() {}

    func exploreModeDidEnter() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            var elapsed: TimeInterval = 0
            for offset in ExploreModeConversionPrompt.presentationOffsetsSeconds {
                let wait = max(0, offset - elapsed)
                elapsed = offset
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard !Task.isCancelled else { return }
                await self?.fireIfEligible()
            }
        }
    }

    func exploreModeDidExit() {
        timerTask?.cancel()
        timerTask = nil
        isPresented = false
    }

    func dismissKeepExploring() {
        isPresented = false
    }

    func exitToCreateAccount() {
        isPresented = false
        AppLaunchController.shared.exitDemoExplore(authIntent: .createAccount)
    }

    func exitToSignIn() {
        isPresented = false
        AppLaunchController.shared.exitDemoExplore(authIntent: .signIn)
    }

    private func fireIfEligible() async {
        guard AppLaunchController.shared.isDemoExperienceActive else { return }
        await waitUntilSafeToPresent()
        guard !Task.isCancelled else { return }
        guard AppLaunchController.shared.isDemoExperienceActive else { return }
        isPresented = true
    }

    private func waitUntilSafeToPresent() async {
        while !Task.isCancelled {
            guard AppLaunchController.shared.isDemoExperienceActive else { return }
            if canPresentWithoutInterrupting() { return }
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    private func canPresentWithoutInterrupting() -> Bool {
        if DemoModeAuthGatePresenter.shared.isPresented { return false }
        let store = AppLaunchController.shared.environment.navigation.store
        if store.presentedSheet != nil { return false }
        if store.presentedFullScreen != nil { return false }
        if AppLaunchController.shared.environment.contentReportPresenter.activeRequest != nil {
            return false
        }
        return true
    }
}

private struct ExploreModeConversionPromptSheet: View {
    @Environment(\.themeColors) private var colors
    @Bindable private var coordinator = ExploreModeConversionPromptCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text(ExploreModeConversionPrompt.title)
                    .experienceStyle(.title3, color: colors.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(ExploreModeConversionPrompt.message)
                    .experienceStyle(.body, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: ExperienceSpacing.sm) {
                ExperienceButton(
                    title: ExploreModeConversionPrompt.createAccountTitle,
                    kind: .primary,
                    accessibilityIdentifier: "explore.conversion.createAccount"
                ) {
                    coordinator.exitToCreateAccount()
                }

                ExperienceButton(
                    title: ExploreModeConversionPrompt.keepExploringTitle,
                    kind: .secondary,
                    accessibilityIdentifier: "explore.conversion.keepExploring"
                ) {
                    coordinator.dismissKeepExploring()
                }

                Button {
                    ExperienceHaptics.play(.selection)
                    coordinator.exitToSignIn()
                } label: {
                    Text(ExploreModeConversionPrompt.signInTitle)
                        .experienceStyle(.callout, color: colors.accent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .experienceTouchTarget()
                .accessibilityIdentifier("explore.conversion.signIn")
            }
        }
        .padding(ExperienceSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceScreenBackground()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
    }
}

struct ExploreModeConversionPromptModifier: ViewModifier {
    @Bindable private var coordinator = ExploreModeConversionPromptCoordinator.shared

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { coordinator.isPresented },
                set: { newValue in
                    if !newValue {
                        coordinator.dismissKeepExploring()
                    }
                }
            )) {
                ExploreModeConversionPromptSheet()
                    .applyThemeEnvironment(AppLaunchController.shared.environment.themeManager.themeEnvironment)
            }
    }
}

extension View {
    func exploreModeConversionPrompt() -> some View {
        modifier(ExploreModeConversionPromptModifier())
    }
}
