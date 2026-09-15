import Foundation

enum ProfileSectionInitialLoad {
    /// True while ``ProfileScreenViewModel`` still owns the first authoritative section payload.
    static func awaitingScreenBootstrap(
        isScreenOwned: Bool,
        snapshot: ProfileState,
        didLoadSection: Bool,
        sectionItemsEmpty: Bool,
        localItemsEmpty: Bool
    ) -> Bool {
        guard isScreenOwned, localItemsEmpty, !didLoadSection, sectionItemsEmpty else { return false }
        return snapshot.phase == .loading || snapshot.didBootstrap
    }
}

@MainActor
final class ProfileSectionFailureGrace {
    private var task: Task<Void, Never>?
    private static let graceNanoseconds: UInt64 = 650_000_000

    func cancel() {
        task?.cancel()
        task = nil
    }

    func scheduleIfNeeded(
        message: String,
        shouldPresent: @escaping @MainActor () -> Bool,
        present: @escaping @MainActor (String) -> Void
    ) {
        cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.graceNanoseconds)
            guard !Task.isCancelled else { return }
            guard shouldPresent() else { return }
            present(message)
        }
    }
}
