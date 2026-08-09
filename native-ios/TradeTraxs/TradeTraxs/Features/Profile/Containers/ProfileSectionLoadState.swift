import Foundation

/// Shared load surface for Profile section containers.
enum ProfileSectionLoadState: Equatable, Sendable {
    case idle
    case loading
    case empty
    case loaded(itemCount: Int)
    case failed(message: String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
