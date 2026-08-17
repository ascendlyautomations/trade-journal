import SwiftUI

/// Shared list-row skeleton stacks for Activity / Explore / Follow / Trades loading.
struct ExperienceListSkeleton: View {
    enum Style {
        case inboxRow
        case tradeCard
        case personRow
        case calendarGrid
        case leaderboard
        case explore
    }

    var style: Style = .inboxRow
    var rowCount: Int = 8

    var body: some View {
        Group {
            switch style {
            case .inboxRow:
                inboxRows
            case .tradeCard:
                tradeCards
            case .personRow:
                personRows
            case .calendarGrid:
                calendarSkeleton
            case .leaderboard:
                leaderboardSkeleton
            case .explore:
                exploreSkeleton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, ExperienceSpacing.sm)
        .accessibilityHidden(true)
        .accessibilityIdentifier("loading.skeleton.\(style)")
    }

    private var inboxRows: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(spacing: ExperienceSpacing.sm) {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 48, height: 48)
                        .overlay(ExperienceSkeleton(height: 48, cornerRadius: 24))
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                            .frame(maxWidth: 160)
                        ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                            .frame(maxWidth: .infinity)
                    }
                    Spacer(minLength: ExperienceSpacing.sm)
                    ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                        .frame(width: 28)
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }
        }
    }

    private var tradeCards: some View {
        VStack(spacing: ExperienceSpacing.md) {
            ForEach(0..<min(rowCount, 5), id: \.self) { _ in
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    HStack {
                        ExperienceSkeleton(height: 18, cornerRadius: ExperienceRadius.xs)
                            .frame(width: 88)
                        Spacer()
                        ExperienceSkeleton(height: 18, cornerRadius: ExperienceRadius.xs)
                            .frame(width: 64)
                    }
                    ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                        .frame(maxWidth: 140)
                    ExperienceSkeleton(height: 96, cornerRadius: ExperienceRadius.md)
                    ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                        .frame(maxWidth: .infinity)
                }
                .padding(ExperienceSpacing.md)
                .padding(.horizontal, ExperienceSpacing.md)
            }
        }
    }

    private var personRows: some View {
        VStack(spacing: ExperienceSpacing.md) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(spacing: ExperienceSpacing.md) {
                    ExperienceSkeleton(height: 48, cornerRadius: 24)
                        .frame(width: 48)
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                            .frame(width: 120)
                        ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                            .frame(width: 80)
                    }
                    Spacer()
                    ExperienceSkeleton(height: 32, cornerRadius: ExperienceRadius.button)
                        .frame(width: 88)
                }
                .padding(.horizontal, ExperienceSpacing.lg)
            }
        }
    }

    private var calendarSkeleton: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack {
                ExperienceSkeleton(height: 22, cornerRadius: ExperienceRadius.xs)
                    .frame(width: 140)
                Spacer()
                ExperienceSkeleton(height: 28, cornerRadius: ExperienceRadius.button)
                    .frame(width: 72)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: ExperienceSpacing.xs), count: 7),
                spacing: ExperienceSpacing.xs
            ) {
                ForEach(0..<35, id: \.self) { _ in
                    ExperienceSkeleton(height: 44, cornerRadius: ExperienceRadius.sm)
                }
            }
            ExperienceSkeleton(height: 56, cornerRadius: ExperienceRadius.md)
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private var leaderboardSkeleton: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            HStack(alignment: .bottom, spacing: ExperienceSpacing.md) {
                podiumPillar(height: 72)
                podiumPillar(height: 96)
                podiumPillar(height: 64)
            }
            .padding(.horizontal, ExperienceSpacing.xl)
            .padding(.top, ExperienceSpacing.md)

            VStack(spacing: ExperienceSpacing.md) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(spacing: ExperienceSpacing.sm) {
                        ExperienceSkeleton(height: 16, cornerRadius: ExperienceRadius.xs)
                            .frame(width: 24)
                        ExperienceSkeleton(height: 40, cornerRadius: 20)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                                .frame(width: 120)
                            ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                                .frame(width: 72)
                        }
                        Spacer()
                        ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                            .frame(width: 48)
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                }
            }
        }
    }

    private func podiumPillar(height: CGFloat) -> some View {
        VStack(spacing: ExperienceSpacing.sm) {
            ExperienceSkeleton(height: 48, cornerRadius: 24)
                .frame(width: 48)
            ExperienceSkeleton(height: height, cornerRadius: ExperienceRadius.md)
        }
        .frame(maxWidth: .infinity)
    }

    private var exploreSkeleton: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            ExperienceSkeleton(height: 18, cornerRadius: ExperienceRadius.xs)
                .frame(width: 160)
                .padding(.horizontal, ExperienceSpacing.md)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ExperienceSpacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                            ExperienceSkeleton(height: 52, cornerRadius: 26)
                                .frame(width: 52)
                            ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                                .frame(width: 100)
                            ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                                .frame(width: 72)
                            ExperienceSkeleton(height: 30, cornerRadius: ExperienceRadius.button)
                        }
                        .padding(ExperienceSpacing.sm)
                        .frame(width: 148, alignment: .leading)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }
            ExperienceSkeleton(height: 18, cornerRadius: ExperienceRadius.xs)
                .frame(width: 180)
                .padding(.horizontal, ExperienceSpacing.md)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ExperienceSpacing.sm) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                            ExperienceSkeleton(height: 72, cornerRadius: ExperienceRadius.sm)
                            ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                                .frame(width: 120)
                            ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                                .frame(width: 80)
                        }
                        .padding(ExperienceSpacing.sm)
                        .frame(width: 168, alignment: .leading)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }
        }
    }
}
