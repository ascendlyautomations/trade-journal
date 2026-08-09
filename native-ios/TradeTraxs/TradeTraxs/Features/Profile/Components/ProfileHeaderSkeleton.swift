import SwiftUI

struct ProfileHeaderSkeleton: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack(alignment: .center, spacing: ExperienceSpacing.md) {
                Circle()
                    .fill(colors.skeleton)
                    .frame(width: 88, height: 88)
                    .overlay {
                        ExperienceSkeleton(height: 88, cornerRadius: 44)
                            .clipShape(Circle())
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    ExperienceSkeleton(height: 20, cornerRadius: ExperienceRadius.xs)
                        .frame(width: 140)
                    ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                        .frame(width: 100)
                    ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                        .frame(width: 180)
                    ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                        .frame(width: 160)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ProfileStatisticsRow(
                metrics: ProfileDisplay.headerMetrics(from: nil),
                isLoading: true
            )

            ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                .frame(maxWidth: .infinity)

            HStack(spacing: ExperienceSpacing.xs) {
                ExperienceSkeleton(height: 32, cornerRadius: ExperienceRadius.button)
                    .frame(width: 96)
                ExperienceSkeleton(height: 32, cornerRadius: ExperienceRadius.button)
                    .frame(width: 72)
                ExperienceSkeleton(height: 32, cornerRadius: ExperienceRadius.button)
                    .frame(width: 32)
                Spacer(minLength: 0)
            }
            .frame(minHeight: ExperienceAccessibility.minTouchTarget, alignment: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading profile")
    }
}
