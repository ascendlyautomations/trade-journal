import Foundation
import Observation

@Observable
@MainActor
final class ThirdPartyAIConsentPresenter {
    var isPresented = false

    private var pendingContinuation: CheckedContinuation<Bool, Never>?
    private var pendingUserID: UserID?

    func ensureConsent(for userID: UserID) async -> Bool {
        if ThirdPartyAIConsentStore.hasConsent(for: userID) {
            return true
        }

        return await withCheckedContinuation { continuation in
            if let pendingContinuation {
                pendingContinuation.resume(returning: false)
                self.pendingContinuation = nil
            }
            pendingUserID = userID
            pendingContinuation = continuation
            isPresented = true
        }
    }

    func confirmContinue() {
        if let pendingUserID {
            ThirdPartyAIConsentStore.recordConsent(for: pendingUserID)
        }
        finish(granted: true)
    }

    func decline() {
        finish(granted: false)
    }

    func handleSheetDismissed() {
        guard isPresented else { return }
        decline()
    }

    private func finish(granted: Bool) {
        isPresented = false
        pendingUserID = nil
        pendingContinuation?.resume(returning: granted)
        pendingContinuation = nil
    }
}

@MainActor
enum ThirdPartyAIConsentGate {
    private static weak var presenter: ThirdPartyAIConsentPresenter?

    static func configure(presenter: ThirdPartyAIConsentPresenter) {
        self.presenter = presenter
    }

    /// Returns false when the user taps Not Now or dismisses the sheet.
    static func ensureConsent(session: any SessionProviding) async -> Bool {
        guard let userID = await session.currentUserID else { return false }
        guard let presenter else { return true }
        return await presenter.ensureConsent(for: userID)
    }
}
