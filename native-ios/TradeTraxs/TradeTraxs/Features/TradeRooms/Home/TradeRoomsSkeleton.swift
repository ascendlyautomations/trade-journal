import SwiftUI

struct TradeRoomsSkeleton: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView {
            LazyVStack(spacing: ExperienceSpacing.sm) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                        Circle()
                            .fill(colors.fillSecondary)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 8) {
                            roundedRect(height: 14).frame(width: 160)
                            roundedRect(height: 12).frame(width: 120)
                            roundedRect(height: 12).frame(maxWidth: .infinity)
                            roundedRect(height: 10).frame(width: 64)
                        }
                    }
                    .padding(ExperienceSpacing.sm)
                    .background(
                        colors.backgroundSecondary.opacity(0.65),
                        in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    )
                    .redacted(reason: .placeholder)
                }
            }
            .padding(ExperienceSpacing.md)
        }
        .accessibilityIdentifier("tradeRooms.skeleton")
    }

    private func roundedRect(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(colors.fillSecondary)
            .frame(height: height)
    }
}
