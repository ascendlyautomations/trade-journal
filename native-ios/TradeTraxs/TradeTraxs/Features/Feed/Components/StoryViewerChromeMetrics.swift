import CoreGraphics

/// Shared insets for full-screen Story viewer chrome (progress, author row, overflow).
enum StoryViewerChromeMetrics {
    static let horizontalInset = ExperienceSpacing.lg
    static let topBreathingRoom = ExperienceSpacing.sm
    static let sectionSpacing = ExperienceSpacing.xs

    /// Top scrim height (header content + fade below).
    static let headerScrimHeight: CGFloat = 148
    /// Extends the gradient upward under the status bar without shifting chrome layout.
    static let headerScrimTopBleed: CGFloat = 44
    static let headerScrimTopOpacity: CGFloat = 0.55
    static let headerScrimMidOpacity: CGFloat = 0.22
}
