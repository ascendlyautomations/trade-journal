import SwiftUI

enum ExperienceAccessibility {
    /// Minimum interactive control size.
    static let minTouchTarget = ExperienceSpacing.minTouchTarget
}

struct MinTouchTargetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: ExperienceAccessibility.minTouchTarget,
                minHeight: ExperienceAccessibility.minTouchTarget
            )
            .contentShape(Rectangle())
    }
}

extension View {
    func experienceTouchTarget() -> some View {
        modifier(MinTouchTargetModifier())
    }

    @ViewBuilder
    func experienceAccessibility(
        label: String,
        hint: String? = nil,
        identifier: String? = nil,
        traits: AccessibilityTraits = []
    ) -> some View {
        let labeled = accessibilityLabel(Text(label))
            .accessibilityAddTraits(traits)
        let hinted: AnyView = {
            if let hint {
                return AnyView(labeled.accessibilityHint(Text(hint)))
            }
            return AnyView(labeled)
        }()
        if let identifier {
            hinted.accessibilityIdentifier(identifier)
        } else {
            hinted
        }
    }
}
