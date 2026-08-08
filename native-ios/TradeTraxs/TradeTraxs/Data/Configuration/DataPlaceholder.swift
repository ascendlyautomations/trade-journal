import Foundation

/// Shared unimplemented / empty responses for repository skeletons.
enum DataPlaceholder {
    static func unimplemented(_ feature: String = #function) -> AppError {
        .notImplemented(feature: feature)
    }

    static func emptyPage<T: Sendable>() -> CursorPage<T> {
        CursorPage(items: [], nextCursor: nil)
    }
}
