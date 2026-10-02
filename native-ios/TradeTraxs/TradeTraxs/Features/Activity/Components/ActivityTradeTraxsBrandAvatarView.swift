import SwiftUI

/// App logo avatar for TradeTraxs system Activity rows (`Image("AppLogo")` — same asset as login branding).
struct ActivityTradeTraxsBrandAvatarView: View {
    var size: CGFloat = 40

    @Environment(\.themeColors) private var colors

    private static let logoAssetName = "AppLogo"

    var body: some View {
        ZStack {
            Circle()
                .fill(colors.secondaryBackground)
            Image(Self.logoAssetName)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .padding(size * 0.06)
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
