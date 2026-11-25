import SwiftUI

enum BroadcastDurationCountdownStyle {
    case banner
    case navigationTitle
}

/// Broadcaster countdown until server `expires_at` (video broadcasts only).
struct BroadcastDurationCountdownView: View {
    let expiresAt: String?
    var style: BroadcastDurationCountdownStyle = .banner
    @Environment(\.themeColors) private var colors

    var body: some View {
        if let expiresAt, !expiresAt.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = BroadcastDurationLimitSupport.remaining(
                    from: expiresAt,
                    now: context.date
                )
                let level = BroadcastDurationLimitSupport.warningLevel(for: remaining)
                let warning = BroadcastDurationLimitSupport.warningCopy(for: level)
                if let remaining, level != .none || remaining > 0 {
                    switch style {
                    case .navigationTitle:
                        Text(
                            "Time left: \(BroadcastDurationLimitSupport.formattedCountdown(remaining: remaining))"
                        )
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(warningTone(level))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("tradeRooms.broadcast.duration")
                    case .banner:
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            HStack(spacing: ExperienceSpacing.xs) {
                                Image(systemName: "clock")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(
                                    "Time left: \(BroadcastDurationLimitSupport.formattedCountdown(remaining: remaining))"
                                )
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                            }
                            .foregroundStyle(warningTone(level))
                            if let warning {
                                Text(warning)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(warningTone(level))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, ExperienceSpacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.fillSecondary.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                        .accessibilityIdentifier("tradeRooms.broadcast.duration")
                    }
                }
            }
        }
    }

    private func warningTone(_ level: BroadcastDurationLimitSupport.WarningLevel) -> Color {
        switch level {
        case .fiveMinutes, .expired:
            return colors.error
        case .fifteenMinutes:
            return colors.secondaryText
        case .none:
            return colors.accent
        }
    }
}