import SwiftUI

struct ExperienceLoadingSpinner: View {
    var label: String = "Loading"

    @Environment(\.themeColors) private var colors

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(colors.accent)
            .experienceAccessibility(label: label, identifier: "loading.spinner")
    }
}

struct ExperienceSkeleton: View {
    var height: CGFloat = 16
    var cornerRadius: CGFloat = ExperienceRadius.xs

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(colors.skeleton)
            .frame(height: height)
            .opacity(reduceMotion ? ExperienceOpacity.muted : 0.55 + 0.35 * abs(sin(phase)))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: true)) {
                    phase = .pi
                }
            }
            .accessibilityHidden(true)
    }
}

struct ExperienceProgressIndicator: View {
    var value: Double
    var total: Double = 1

    @Environment(\.themeColors) private var colors

    var body: some View {
        ProgressView(value: value, total: total)
            .tint(colors.accent)
            .experienceAccessibility(
                label: "Progress",
                hint: "\(Int((value / max(total, 0.0001)) * 100)) percent",
                identifier: "progress"
            )
    }
}

struct ExperienceToast: View {
    let message: String
    var tone: BannerTone = .success

    @Environment(\.themeColors) private var colors

    var body: some View {
        let toneColor = tone.color(in: colors)
        HStack(spacing: ExperienceSpacing.xs) {
            ExperienceIcon(icon: tone.icon, size: .sm, color: toneColor)
            Text(message)
                .experienceStyle(.callout, color: colors.primaryText)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .background(colors.cardBackground)
        .clipShape(Capsule())
        .experienceElevation(.medium)
        .experienceAccessibility(label: message, identifier: "toast")
    }
}

struct ExperienceBanner: View {
    let title: String
    var message: String? = nil
    var tone: BannerTone = .info
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        let toneColor = tone.color(in: colors)
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            ExperienceIcon(icon: tone.icon, size: .md, color: toneColor)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(title)
                    .experienceStyle(.headline, color: colors.primaryText)
                if let message {
                    Text(message)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
                if let actionTitle, let action {
                    ExperienceButton(title: actionTitle, kind: .text, action: action)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(ExperienceSpacing.md)
        .background(toneColor.opacity(ExperienceOpacity.faint))
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .experienceAccessibility(label: title, hint: message, identifier: "banner.\(tone)")
    }
}

struct ExperienceEmptyState: View {
    var icon: AppIcon = .empty
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
                    .experienceStyle(.title3, color: colors.primaryText)
            } icon: {
                ExperienceIcon(icon: icon, size: .hero, color: colors.tertiaryText)
            }
        } description: {
            if let message {
                Text(message)
                    .experienceStyle(.body, color: colors.secondaryText)
            }
        } actions: {
            if let actionTitle, let action {
                ExperienceButton(title: actionTitle, kind: .primary, action: action)
                    .frame(maxWidth: 280)
            }
        }
        .experienceAccessibility(label: title, hint: message, identifier: "emptyState")
    }
}

struct ExperienceErrorState: View {
    let title: String
    var message: String? = nil
    var retryTitle: String = "Try Again"
    var onRetry: (() -> Void)? = nil

    var body: some View {
        ExperienceEmptyState(
            icon: .error,
            title: title,
            message: message,
            actionTitle: onRetry == nil ? nil : retryTitle,
            action: onRetry
        )
    }
}

struct ExperienceFeedbackHost: View {
    let state: FeedbackState
    var onRetry: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            ExperienceLoadingSpinner()
        case .syncing:
            HStack(spacing: ExperienceSpacing.xs) {
                ExperienceLoadingSpinner(label: "Syncing")
                Text("Syncing…")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        case .empty(let message):
            ExperienceEmptyState(title: "Nothing here yet", message: message)
        case .offline(let message):
            ExperienceBanner(title: "You're offline", message: message, tone: .offline, actionTitle: "Retry", action: onRetry)
        case .failure(let message, let retryable):
            ExperienceErrorState(
                title: "Something went wrong",
                message: message,
                onRetry: retryable ? onRetry : nil
            )
        case .success(let message):
            ExperienceToast(message: message, tone: .success)
        }
    }
}
