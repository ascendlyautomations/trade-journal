import Foundation
import Observation

/// Shared success copy for explicit Settings / Profile save actions.
nonisolated enum SaveSuccessToastMessage {
    static let profileUpdated = "Profile Updated"
    static let settingsSaved = "Settings Saved"
    static let changesSaved = "Changes Saved"
}

/// Presents a brief non-blocking success toast after authoritative saves.
@Observable
@MainActor
final class SaveSuccessConfirmationCenter {
    static let shared = SaveSuccessConfirmationCenter()

    private(set) var message: String?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func present(_ message: String, duration: Duration = .seconds(1.75)) {
        dismissTask?.cancel()
        self.message = message
        let token = message
        dismissTask = Task {
            try? await Task.sleep(for: duration)
            await MainActor.run {
                guard self.message == token else { return }
                self.message = nil
            }
        }
    }

    func clear() {
        dismissTask?.cancel()
        dismissTask = nil
        message = nil
    }
}
