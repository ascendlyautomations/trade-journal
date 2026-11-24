import SwiftUI

private struct TraxsProPreviewReadOnlyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var traxsProPreviewReadOnly: Bool {
        get { self[TraxsProPreviewReadOnlyKey.self] }
        set { self[TraxsProPreviewReadOnlyKey.self] = newValue }
    }
}

/// Shared sample-data chrome for every TraxsPro full-screen preview (Dashboard reference layout).
struct TraxsProSampleDataHeader: View {
    let unlockFeature: ProFeatureKind
    var subtitle: String = MonetizationPlanCopy.traxsProPreviewGenericSubtitle
    var onExit: () -> Void
    var onUnlock: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            sampleDataIcon
            VStack(alignment: .leading, spacing: 2) {
                Text("Sample Data")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(colors.primaryText)
                Text(subtitle)
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: ExperienceSpacing.xxs)

            VStack(alignment: .trailing, spacing: 6) {
                Button(MonetizationPlanCopy.exitPreviewButtonTitle, action: onExit)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
                    .accessibilityIdentifier("traxspro.preview.exit")

                if canPresentPaywall {
                    Button(action: onUnlock) {
                        Text(MonetizationPlanCopy.paywallUnlockTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(colors.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(colors.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("traxspro.preview.unlock")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.surfacePrimary)
        .overlay {
            if colorScheme == .light {
                Rectangle()
                    .strokeBorder(
                        colors.border.opacity(ExperienceDashboardSurface.LightChrome.borderOpacity),
                        lineWidth: ExperienceBorder.hairline
                    )
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .background(colors.border.opacity(0.6))
        }
        .accessibilityIdentifier("traxspro.preview.banner")
    }

    private var sampleDataIcon: some View {
        Image(systemName: "doc.text.magnifyingglass")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.accent)
            .accessibilityHidden(true)
    }

    private var canPresentPaywall: Bool {
        ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        )
    }
}