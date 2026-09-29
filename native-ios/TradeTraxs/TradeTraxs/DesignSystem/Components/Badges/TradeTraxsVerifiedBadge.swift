import SwiftUI

/// TradeTraxs verification mark — blue hexagon with white “T” (not a generic platform check).
struct TradeTraxsVerifiedBadge: View {
    enum Size: Sendable {
        /// Beside usernames in dense lists (DM rows, leaderboard, members).
        case inline
        /// Standard inline with body / subheadline text.
        case compact
        /// Profile header and prominent identity rows.
        case standard

        var dimension: CGFloat {
            switch self {
            case .inline: 11
            case .compact: 12
            case .standard: 14
            }
        }

        var letterPointSize: CGFloat {
            switch self {
            case .inline: 7
            case .compact: 7.5
            case .standard: 9
            }
        }
    }

    var size: Size = .inline
    var accessibilityLabel: String = "Verified"

    @Environment(\.themeColors) private var colors

    var body: some View {
        ZStack {
            TradeTraxsVerifiedHexagon()
                .fill(colors.accent)
            Text("T")
                .font(.system(size: size.letterPointSize, weight: .heavy, design: .default))
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.5)
                .accessibilityHidden(true)
        }
        .frame(width: size.dimension, height: size.dimension)
        .alignmentGuide(.firstTextBaseline) { dimensions in
            dimensions[VerticalAlignment.center]
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct TradeTraxsVerifiedHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<6 {
            let degrees = CGFloat(index) * 60 - 30
            let radians = degrees * .pi / 180
            let point = CGPoint(
                x: center.x + radius * cos(radians),
                y: center.y + radius * sin(radians)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
