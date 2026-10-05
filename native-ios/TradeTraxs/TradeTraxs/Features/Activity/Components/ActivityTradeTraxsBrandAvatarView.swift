import SwiftUI

/// App logo avatar for TradeTraxs system Activity rows (`Image("AppLogo")` — same asset as login branding).
struct ActivityTradeTraxsBrandAvatarView: View {
    var size: CGFloat = 40

    @Environment(\.themeColors) private var colors

    private static let logoAssetName = "AppLogo"
    /// In-circle fill for `AppLogo` before the circular clip (~10% zoom-out step from 1.10).
    private static let logoFillScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(colors.secondaryBackground)
            Image(Self.logoAssetName)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .scaleEffect(Self.logoFillScale)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(colors.border, lineWidth: ExperienceBorder.hairline)
        }
        .accessibilityLabel("TradeTraxs")
        .accessibilityIdentifier("activity.avatar.tradetraxs")
    }
}
