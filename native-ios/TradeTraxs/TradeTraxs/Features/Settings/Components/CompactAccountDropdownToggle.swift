import SwiftUI

/// Visually smaller account-dropdown toggle with a full-size touch target.
struct CompactAccountDropdownToggle: View {
    @Binding var isOn: Bool
    let accessibilityIdentifier: String
    let isOnAccessibilityValue: Bool

    @Environment(\.themeColors) private var colors

    var body: some View {
        Toggle(isOn: $isOn) {
            EmptyView()
        }
        .labelsHidden()
        .tint(colors.accent)
        .scaleEffect(0.76)
        .frame(
            width: ExperienceAccessibility.minTouchTarget,
            height: ExperienceAccessibility.minTouchTarget
        )
        .contentShape(Rectangle())
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel("Show in account dropdowns")
        .accessibilityValue(isOnAccessibilityValue ? "On" : "Off")
    }
}
