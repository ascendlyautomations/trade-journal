import SwiftUI

/// Keeps a dashboard block from reporting a width larger than it was offered.
///
/// Some HStacks round one pixel past the proposal. Inside the Dashboard's vertical
/// scroll view that extra pixel becomes horizontal panning. The block is placed
/// in the offered width, so its contents still use the normal margins.
struct ProposedWidthClamp: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let fitted = child.sizeThatFits(proposal)
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = min(fitted.width, proposed)
        } else {
            width = fitted.width
        }
        return CGSize(width: width, height: fitted.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height)
        )
    }
}
