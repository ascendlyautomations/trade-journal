import SwiftUI

/// Compact prop-aware Dashboard card — actionable rules summary.
struct PropFirmStatusCard: View {
    let snapshot: PropFirmStatusSnapshot
    let onOpenDetails: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prop Firm Status")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(snapshot.accountName)
                        .experienceStyle(.headline, color: colors.primaryText)
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: ExperienceSpacing.md) {
                metric(
                    "Balance",
                    DashboardViewModel.money(snapshot.currentBalance),
                    tone: .neutral
                )
                metric(
                    "Cycle P&L",
                    DashboardViewModel.money(snapshot.cyclePnL),
                    tone: snapshot.cyclePnL >= 0 ? .positive : .negative
                )
                metric(
                    "To DD",
                    DashboardViewModel.money(snapshot.distanceToDD),
                    tone: snapshot.distanceDanger || snapshot.distanceToDD < 0 ? .negative : .positive
                )
            }

            if let target = snapshot.profitTarget, target > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Profit target")
                            .experienceStyle(.caption2, color: colors.secondaryText)
                        Spacer()
                        Text("\(Int(snapshot.profitTargetProgress.rounded()))%")
                            .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(colors.primaryText)
                    }
                    ProgressView(value: min(max(snapshot.profitTargetProgress / 100, 0), 1))
                        .tint(snapshot.isPassed ? colors.profit : colors.accent)
                }
            }

            HStack(spacing: ExperienceSpacing.sm) {
                ExperienceTag(title: snapshot.phaseLabel, tone: .info)
                if let required = snapshot.winningDaysRequired, required > 0 {
                    ExperienceTag(
                        title: "Days \(snapshot.winningDays)/\(required)",
                        tone: snapshot.winningDays >= required ? .success : .info
                    )
                }
                if snapshot.consistencyRequired {
                    ExperienceTag(
                        title: snapshot.consistencyMet ? "Consistent" : "Consistency",
                        tone: snapshot.consistencyMet ? .success : .warning
                    )
                }
            }

            Button(action: onOpenDetails) {
                HStack {
                    Text("View Prop Firm Details")
                        .experienceStyle(.subheadline, color: colors.accent)
                        .fontWeight(.semibold)
                    Spacer()
                    ExperienceIcon(icon: .forward, size: .sm, color: colors.accent)
                }
                .padding(.top, ExperienceSpacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.propFirm.details")
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.55), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(
                    snapshot.riskTone == .negative
                        ? colors.loss.opacity(0.45)
                        : colors.border.opacity(0.4),
                    lineWidth: ExperienceBorder.hairline
                )
        }
        .accessibilityIdentifier("dashboard.propFirm.status")
    }

    private var statusBadge: some View {
        Text(snapshot.statusLabel)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(badgeForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeForeground.opacity(0.14), in: Capsule())
    }

    private var badgeForeground: Color {
        switch snapshot.riskTone {
        case .positive: return colors.profit
        case .negative: return colors.loss
        case .neutral: return colors.accent
        }
    }

    private func metric(_ label: String, _ value: String, tone: DashboardMetricTone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .experienceStyle(.caption2, color: colors.secondaryText)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(toneColor(tone))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toneColor(_ tone: DashboardMetricTone) -> Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }
}
