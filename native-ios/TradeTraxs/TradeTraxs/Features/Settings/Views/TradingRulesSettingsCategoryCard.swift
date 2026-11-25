import SwiftUI

/// Collapsible settings category with configured-rule count and optional per-section reset menu.
struct TradingRulesSettingsCategoryCard<Content: View, ResetMenu: View>: View {
    let title: String
    let configuredCount: Int
    @Binding var isExpanded: Bool
    let resetID: String
    var showsReset: Bool = true
    @ViewBuilder let resetMenu: () -> ResetMenu
    @ViewBuilder let content: () -> Content

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                ExperienceDivider()
                    .padding(.horizontal, ExperienceSpacing.md)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, ExperienceSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(prominence: .standard)
        .accessibilityElement(children: isExpanded ? .contain : .ignore)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .multilineTextAlignment(.leading)
                    configuredCountBadge
                    Spacer(minLength: ExperienceSpacing.xs)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(title), \(configuredCount) configured, \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")

            if showsReset {
                Menu(content: resetMenu) {
                    Text("Reset")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(resetID)
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
    }

  @ViewBuilder
    private var configuredCountBadge: some View {
        Text("\(configuredCount)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(configuredCount > 0 ? colors.accent : colors.tertiaryText)
            .padding(.horizontal, ExperienceSpacing.xs)
            .padding(.vertical, 2)
            .background(
                (configuredCount > 0 ? colors.accent : colors.fillTertiary).opacity(0.18),
                in: Capsule()
            )
            .accessibilityLabel("\(configuredCount) rules configured")
    }
}