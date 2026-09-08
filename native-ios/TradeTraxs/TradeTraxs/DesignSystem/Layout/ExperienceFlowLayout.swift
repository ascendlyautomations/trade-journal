import SwiftUI

/// Left-to-right flow layout that wraps subviews onto additional rows when width is exceeded.
struct ExperienceFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    init(spacing: CGFloat = 4, rowSpacing: CGFloat = 4) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let measured = laidOutSize(subviews: subviews, maxWidth: maxWidth)
        if maxWidth.isFinite, maxWidth > 0 {
            return CGSize(width: maxWidth, height: measured.height)
        }
        return measured
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }

    private func laidOutSize(subviews: Subviews, maxWidth: CGFloat) -> CGSize {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        let wraps = maxWidth.isFinite && maxWidth > 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if wraps, x > 0, x + size.width > maxWidth {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        maxRowWidth = max(maxRowWidth, max(0, x - spacing))
        let width = wraps ? maxRowWidth : max(0, x - spacing)
        return CGSize(width: width, height: y + rowHeight)
    }
}
