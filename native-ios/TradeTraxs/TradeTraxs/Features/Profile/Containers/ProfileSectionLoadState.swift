import Foundation

/// Shared load surface for Profile section containers.
enum ProfileSectionLoadState: Equatable, Sendable {
    case idle
    case loading
    case empty
    case contentLocked
    case loaded(itemCount: Int)
    case failed(message: String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// True once the section has shown real or empty content (not the initial skeleton).
    var hasSettledPresentation: Bool {
        switch self {
        case .loaded, .empty, .contentLocked, .failed:
            return true
        case .idle, .loading:
            return false
        }
    }

    /// Keeps the last settled surface visible while a background refresh toggles ``loading``.
    func preservingSettledContent(hasSettledLoad: Bool, itemCount: Int) -> ProfileSectionLoadState {
        guard hasSettledLoad, isLoading else { return self }
        if itemCount > 0 {
            return .loaded(itemCount: itemCount)
        }
        return .empty
    }
}
