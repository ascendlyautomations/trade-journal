import SwiftUI

struct DailyCheckInCard: View {
    @Bindable var store: TraderDailyCheckInStore
    let onTap: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ExperienceSpacing.md) {
                ZStack {
                    Circle()
                        .fill(store.isCompletedToday ? colors.profit.opacity(0.15) : colors.accent.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: store.isCompletedToday ? "checkmark.circle.fill" : "sun.horizon.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(store.isCompletedToday ? colors.profit : colors.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Check-In")
                        .experienceStyle(.headline, color: colors.primaryText)
                    Text(subtitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(ExperienceSpacing.md)
            .background(colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dailyCheckIn.card")
        .accessibilityLabel(
            store.isCompletedToday
                ? "Daily Check-In. Completed today."
                : "Daily Check-In. Log how you're feeling today."
        )
    }

    private var subtitle: String {
        if store.isCompletedToday {
            return "Completed today"
        }
        return "Log how you're feeling today"
    }
}
