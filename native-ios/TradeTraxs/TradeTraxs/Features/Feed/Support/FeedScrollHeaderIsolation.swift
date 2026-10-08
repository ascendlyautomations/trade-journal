import Foundation

/// Reversible diagnostic switch — Feed-only. Does not affect Dashboard or shared scroll modifiers.
enum FeedScrollHeaderIsolation {
    /// When `true`, Feed scroll-to-hide is off: navigation bar and category strip stay visible; scroll listener inactive.
    /// Set to `false` to restore scroll-aware header behavior.
    static let suppressScrollToHide = false
}
