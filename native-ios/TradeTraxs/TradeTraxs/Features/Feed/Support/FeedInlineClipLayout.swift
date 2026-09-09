import CoreGraphics
import UIKit

/// Regular Feed → All inline clip media framing (not the immersive Clips pager).
nonisolated enum FeedInlineClipLayout {
    /// ~50–55% of usable scroll viewport height on typical phones → ~430–460pt at 390pt width.
    static let screenHeightFraction: CGFloat = 0.55
    static let minMediaHeight: CGFloat = 280
    static let maxMediaHeightFloor: CGFloat = 400
    static let maxMediaHeightCeiling: CGFloat = 480
    /// Modest portrait boost so header + video + caption + engagement fit one viewport.
    static let inlineMediaHeightBoost: CGFloat = 38
    /// Rough chrome subtracted from screen height (status + nav + tab bar).
    static let verticalChromeAllowance: CGFloat = 60

    static func maxMediaHeight(screenBounds: CGRect = UIScreen.main.bounds) -> CGFloat {
        let usable = max(screenBounds.height - verticalChromeAllowance, minMediaHeight)
        let derived = usable * screenHeightFraction
        let capped = min(maxMediaHeightCeiling, max(maxMediaHeightFloor, derived))
        return capped + inlineMediaHeightBoost
    }

    /// Fixed media region for inline Feed — caps tall portrait clips; video aspect-fits inside.
    static func containerSize(
        containerWidth: CGFloat,
        videoAspectRatio: CGFloat
    ) -> CGSize {
        let width = max(containerWidth, 1)
        let naturalHeight = max(width / max(videoAspectRatio, 0.01), FeedMediaLayout.minHeight)
        let height = min(naturalHeight, maxMediaHeight())
        return CGSize(width: width, height: height)
    }

    /// Portrait placeholder aspect before `VideoPresentationInfo` loads.
    static let placeholderAspectRatio: CGFloat = 9.0 / 16.0
}
