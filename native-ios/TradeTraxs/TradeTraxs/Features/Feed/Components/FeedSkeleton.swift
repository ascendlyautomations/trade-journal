import SwiftUI

struct FeedSkeleton: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ExperienceSpacing.md) {
                        ForEach(0..<5, id: \.self) { _ in
                            VStack(spacing: ExperienceSpacing.xs) {
                                ExperienceSkeleton(height: 64, cornerRadius: 32)
                                    .frame(width: 64)
                                ExperienceSkeleton(height: 10, cornerRadius: ExperienceRadius.xs)
                                    .frame(width: 48)
                            }
                        }
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.sm)
                }

                Rectangle()
                    .fill(colors.border.opacity(0.4))
                    .frame(height: ExperienceBorder.hairline)

                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: ExperienceSpacing.sm) {
                            ExperienceSkeleton(height: 36, cornerRadius: 18)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                                    .frame(maxWidth: 120)
                                ExperienceSkeleton(height: 10, cornerRadius: ExperienceRadius.xs)
                                    .frame(maxWidth: 80)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.vertical, ExperienceSpacing.sm)

                        ExperienceSkeleton(height: 280, cornerRadius: 0)

                        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                            ExperienceSkeleton(height: 18, cornerRadius: ExperienceRadius.xs)
                                .frame(maxWidth: 140)
                            ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(ExperienceSpacing.md)
                    }
                }
            }
        }
        .scrollDisabled(true)
        .accessibilityIdentifier("feed.skeleton")
    }
}
