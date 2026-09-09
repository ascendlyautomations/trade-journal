import CoreGraphics
import Foundation

#if DEBUG
/// DEBUG scroll lifecycle for dedicated Clips pager — one line per milestone.
nonisolated enum ClipsPagerScrollProbe {
    static func dragBegin(index: Int, offset: CGFloat, viewportHeight: CGFloat) {
        print(
            "[ClipsPagerScroll] event=dragBegin index=\(index) offset=\(format(offset)) viewportHeight=\(format(viewportHeight))"
        )
    }

    static func willEndDragging(
        velocityY: CGFloat,
        currentOffset: CGFloat,
        targetOffset: CGFloat,
        targetIndex: Int,
        viewportHeight: CGFloat
    ) {
        print(
            """
            [ClipsPagerScroll] event=willEndDragging velocityY=\(format(velocityY)) \
            currentOffset=\(format(currentOffset)) targetOffset=\(format(targetOffset)) \
            targetIndex=\(targetIndex) viewportHeight=\(format(viewportHeight))
            """
        )
    }

    static func decelerationEnded(offset: CGFloat, resolvedIndex: Int, viewportHeight: CGFloat) {
        print(
            """
            [ClipsPagerScroll] event=decelerationEnded offset=\(format(offset)) \
            resolvedIndex=\(resolvedIndex) viewportHeight=\(format(viewportHeight))
            """
        )
    }

    static func programmaticScroll(from: Int, to: Int, animated: Bool, reason: String) {
        print(
            """
            [ClipsPagerScroll] event=programmaticScroll from=\(from) to=\(to) \
            animated=\(animated) reason=\(reason)
            """
        )
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
#else
nonisolated enum ClipsPagerScrollProbe {
    static func dragBegin(index: Int, offset: CGFloat, viewportHeight: CGFloat) {}
    static func willEndDragging(
        velocityY: CGFloat,
        currentOffset: CGFloat,
        targetOffset: CGFloat,
        targetIndex: Int,
        viewportHeight: CGFloat
    ) {}
    static func decelerationEnded(offset: CGFloat, resolvedIndex: Int, viewportHeight: CGFloat) {}
    static func programmaticScroll(from: Int, to: Int, animated: Bool, reason: String) {}
}
#endif
