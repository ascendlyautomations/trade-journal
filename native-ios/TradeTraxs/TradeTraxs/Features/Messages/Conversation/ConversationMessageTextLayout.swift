import UIKit
import SwiftUI

/// Caps multiline message text at ``maxWidth`` while preserving intrinsic width for short strings.
///
/// Unlike ``View/frame(maxWidth:)``, this layout asks the text subview for its ideal width up to the cap
/// and sizes itself to that answer — short DMs stay compact.
struct ConversationMessageTextLayout: Layout {
    var maxWidth: CGFloat
    var horizontalAlignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let capped = cappedWidth(from: proposal.width)
        return subview.sizeThatFits(
            ProposedViewSize(width: capped, height: proposal.height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let capped = cappedWidth(from: bounds.width)
        let size = subview.sizeThatFits(
            ProposedViewSize(width: capped, height: bounds.height)
        )
        let originX: CGFloat
        switch horizontalAlignment {
        case .trailing:
            originX = bounds.maxX - size.width
        case .center:
            originX = bounds.midX - (size.width / 2)
        default:
            originX = bounds.minX
        }
        subview.place(
            at: CGPoint(x: originX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: size.width, height: size.height)
        )
    }

    private func cappedWidth(from proposed: CGFloat?) -> CGFloat? {
        guard let proposed, proposed.isFinite else { return maxWidth }
        return min(proposed, maxWidth)
    }
}

extension ConversationMessageTextLayout {
    /// UIKit reference width for unit tests — mirrors body font wrapping up to ``maxWidth``.
    static func referenceTextWidth(
        _ text: String,
        maxWidth: CGFloat,
        font: UIFont = UIFont.preferredFont(forTextStyle: .body)
    ) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return min(maxWidth, ceil(max(rect.width, 1)))
    }
}
