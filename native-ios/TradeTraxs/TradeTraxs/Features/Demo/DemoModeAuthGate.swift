import SwiftUI

@Observable
@MainActor
final class DemoModeAuthGatePresenter {
    static let shared = DemoModeAuthGatePresenter()

    var isPresented = false

    func requireAuthentication() {
        isPresented = true
    }
}

struct DemoModeAuthGateModifier: ViewModifier {
    @Bindable private var presenter = DemoModeAuthGatePresenter.shared
    @Bindable private var launchController = AppLaunchController.shared

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Create an account to use this feature.",
                isPresented: $presenter.isPresented,
                titleVisibility: .visible
            ) {
                Button("Create Account") {
                    launchController.exitDemoExplore(authIntent: .createAccount)
                }
                Button("Sign In") {
                    launchController.exitDemoExplore(authIntent: .signIn)
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

extension View {
    func demoModeAuthGate() -> some View {
        modifier(DemoModeAuthGateModifier())
    }
}

enum DemoProtectedNavigation {
    static func interceptIfNeeded(_ destination: AppDestination) -> Bool {
        guard AppLaunchController.shared.isDemoExperienceActive else { return false }
        switch destination {
        case .compose:
            DemoModeAuthGatePresenter.shared.requireAuthentication()
            return true
        case .sheet(let sheet):
            guard sheetRequiresAuth(sheet) else { return false }
            DemoModeAuthGatePresenter.shared.requireAuthentication()
            return true
        case .fullScreen(let cover):
            guard coverRequiresAuth(cover) else { return false }
            DemoModeAuthGatePresenter.shared.requireAuthentication()
            return true
        default:
            return false
        }
    }

    static func interceptComposeIfNeeded(_ kind: ComposeKind) -> Bool {
        guard AppLaunchController.shared.isDemoExperienceActive else { return false }
        DemoModeAuthGatePresenter.shared.requireAuthentication()
        return true
    }

    private static func sheetRequiresAuth(_ sheet: SheetDestination) -> Bool {
        switch sheet {
        case .composeChooser, .quickTrade, .dailyCheckIn, .tradeImportReminder:
            return true
        default:
            return false
        }
    }

    private static func coverRequiresAuth(_ cover: FullScreenDestination) -> Bool {
        switch cover {
        case .addTrade, .editTrade, .importCSV, .newPost, .newAchievement, .newReel, .newStory, .withdrawal:
            return true
        default:
            return false
        }
    }
}
