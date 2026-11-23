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

nonisolated enum TraxsProPreviewBannerStyle: Sendable {
    case standard
    case compact
}

/// Persistent chrome for TraxsPro interactive previews (Reports + Dashboard).
struct TraxsProPreviewSampleDataBanner: View {
    let unlockFeature: ProFeatureKind
    var subtitle: String = MonetizationPlanCopy.traxsProPreviewGenericSubtitle
    var style: TraxsProPreviewBannerStyle = .standard
    var onExit: () -> Void
    var onUnlock: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            switch style {
            case .standard:
                standardBanner
            case .compact:
                compactBanner
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, style == .compact ? ExperienceSpacing.xs : ExperienceSpacing.sm)
        .background(colors.surfacePrimary.opacity(0.98))
        .overlay(alignment: .bottom) {
            Divider()
                .background(colors.border.opacity(0.6))
        }
        .accessibilityIdentifier("traxspro.preview.banner")
    }

    private var standardBanner: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                sampleDataIcon(compact: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sample Data")
                        .experienceStyle(.headline, color: colors.primaryText)
                    Text(subtitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: ExperienceSpacing.xs)
                Button(MonetizationPlanCopy.exitPreviewButtonTitle, action: onExit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
                    .accessibilityIdentifier("traxspro.preview.exit")
            }

            if canPresentPaywall {
                Button(action: onUnlock) {
                    Text(MonetizationPlanCopy.paywallUnlockTitle)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("traxspro.preview.unlock")
            }
        }
    }

    private var compactBanner: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            sampleDataIcon(compact: true)
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
    }

    private func sampleDataIcon(compact: Bool) -> some View {
        Image(systemName: "doc.text.magnifyingglass")
            .font(compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
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