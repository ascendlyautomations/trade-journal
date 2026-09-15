import SwiftUI

struct DailyCheckInCard: View {
    @Bindable var store: TraderDailyCheckInStore
    let onTap: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        DashboardQuickActionRow(
            title: "Daily Check-In",
            subtitle: subtitle,
            accessibilityIdentifier: "dailyCheckIn.card",
            icon: {
                ZStack {
                    Circle()
                        .fill(
                            store.isCompletedToday
                                ? colors.profit.opacity(0.15)
                                : colors.accent.opacity(0.12)
                        )
                        .frame(
                            width: DashboardQuickActionStyle.iconDiameter,
                            height: DashboardQuickActionStyle.iconDiameter
                        )
                    Image(systemName: store.isCompletedToday ? "checkmark.circle.fill" : "sun.horizon.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(store.isCompletedToday ? colors.profit : colors.accent)
                }
            },
            onTap: onTap
        )
    }

    private var subtitle: String {
        if store.isCompletedToday {
            return "Completed today"
        }
        return "Log how you're feeling today"
    }
}
