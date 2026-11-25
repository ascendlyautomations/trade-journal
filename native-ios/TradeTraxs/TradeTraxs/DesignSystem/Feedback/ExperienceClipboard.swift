import UIKit

/// Copies text to the pasteboard and presents the global success toast when it succeeds.
@MainActor
enum ExperienceClipboard {
    static let copiedToastMessage = "Copied"
    private static let dedupeInterval: Duration = .milliseconds(450)
    private static var lastToastPresentedAt: ContinuousClock.Instant?

    @discardableResult
    static func copy(_ string: String?, showsConfirmationToast: Bool = true) -> Bool {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return false }
        UIPasteboard.general.string = trimmed
        if showsConfirmationToast {
            presentCopiedToastIfNeeded()
        }
        return true
    }

    private static func presentCopiedToastIfNeeded() {
        let now = ContinuousClock.now
        if let last = lastToastPresentedAt, now - last < dedupeInterval {
            return
        }
        lastToastPresentedAt = now
        SaveSuccessConfirmationCenter.shared.present(copiedToastMessage)
    }
}