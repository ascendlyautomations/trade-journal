import Foundation

/// Distinguishes which on-screen program video renderer is active (loading is per-surface).
enum BroadcastProgramVideoSurface: Equatable {
    case inlineExpanded
    case cornerChat
    case sheetFullscreen
    case floatingMini
    /// Invisible 1×1 holder while the corner overlay is swiped away — must not drive loading UI.
    case cornerDismissedHold
}