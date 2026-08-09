import SwiftUI

/// Compact Instagram-style Profile section picker — monochrome SF Symbols, no horizontal scroll.
struct ProfileSectionPicker: View {
    @Binding var selection: ProfileSection

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProfileSection.allCases) { section in
                sectionButton(section)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profile sections")
    }

    private func sectionButton(_ section: ProfileSection) -> some View {
        let isSelected = selection == section
        return Button {
            guard selection != section else { return }
            ExperienceMotion.withAnimation(
                ExperienceMotion.selection,
                reduceMotion: reduceMotion
            ) {
                selection = section
            }
        } label: {
            Image(systemName: section.systemImage)
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? colors.accent : colors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Capsule()
                            .fill(colors.accent)
                            .frame(height: 2)
                            .padding(.horizontal, ExperienceSpacing.sm)
                            .matchedGeometryEffect(
                                id: "profile.section.indicator",
                                in: indicatorNamespace
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityHint(section.accessibilityHint)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("profile.section.\(section.rawValue)")
    }
}
