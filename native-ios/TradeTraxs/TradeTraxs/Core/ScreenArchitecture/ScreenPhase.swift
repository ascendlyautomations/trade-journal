import Foundation

/// Canonical load phase shared by every screen-owned ``ScreenStateModeling`` snapshot.
///
/// Feature states may keep a local `Phase` enum for historical call sites; map into this
/// type via ``ScreenStateModeling/screenPhase``.
enum ScreenPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String?)
}

/// Pagination fields that paginated screens expose through ``ScreenStateModeling``.
struct ScreenPaginationSnapshot: Equatable, Sendable {
    var nextCursor: String?
    var hasMore: Bool
    var isLoadingMore: Bool

    static let none = ScreenPaginationSnapshot(
        nextCursor: nil,
        hasMore: false,
        isLoadingMore: false
    )
}
