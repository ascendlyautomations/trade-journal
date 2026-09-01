import SwiftUI

/// Monochrome bank/building glyph — matches the former Profile Accounts tab picker icon.
enum ProfileBankIcon {
    static let systemName = AppIcon.payouts.systemName

    static func image(
        weight: Font.Weight = .regular,
        size: CGFloat = 20,
        color: Color
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color)
    }
}
