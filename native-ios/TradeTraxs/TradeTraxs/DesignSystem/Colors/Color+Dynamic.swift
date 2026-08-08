import SwiftUI
import UIKit

extension Color {
    /// Adaptive color that tracks light/dark appearances.
    static func experience(
        light: UIColor,
        dark: UIColor
    ) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }

    static func experience(
        lightHex: UInt32,
        darkHex: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) -> Color {
        experience(
            light: UIColor(hex: lightHex, alpha: lightAlpha),
            dark: UIColor(hex: darkHex, alpha: darkAlpha)
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
