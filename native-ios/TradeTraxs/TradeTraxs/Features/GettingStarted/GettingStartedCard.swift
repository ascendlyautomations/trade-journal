import SwiftUI

struct GettingStartedCard: View {
    @Bindable var store: GettingStartedStore
    let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displaysCollapsed: Bool {
        if ContextualTourCoordinator.shared.measures(.dashboardGettingStarted) {
            return false
        }
        return store.isCollapsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            header
            if !displaysCollapsed {
                progressBar
                taskList
            }
        }
        .padding(ExperienceSpacing.md)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.card)
        .contextualTourTarget(.dashboardGettingStarted)
        .accessibilityIdentifier("gettingStarted.card")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            if displaysCollapsed {
                Button {
                    ExperienceMotion.withAnimation(ExperienceMotion.selection, reduceMotion: reduceMotion) {
                        store.toggleCollapsed()
                    }
                } label: {
                    HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                        headerTitles
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colors.secondaryText)
                            .frame(width: 28, height: 28)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Expand Getting Started")
            } else {
                headerTitles
                Spacer(minLength: 0)
                Button {
                    ExperienceMotion.withAnimation(ExperienceMotion.selection, reduceMotion: reduceMotion) {
                        store.toggleCollapsed()
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.secondaryText)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Collapse Getting Started")
            }

            if store.canPermanentlyDismiss {
                Button {
                    store.dismissForSession()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.secondaryText)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Dismiss Getting Started")
                .accessibilityIdentifier("gettingStarted.dismiss")
            }
        }
    }

    private var headerTitles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Getting Started")
                .experienceStyle(.headline, color: colors.primaryText)
            Text("\(store.progress.completedCount) of \(store.progress.totalCount) complete")
                .experienceStyle(.caption, color: colors.secondaryText)
        }
    }

    private var progressBar: some View {
        ProgressView(value: store.progress.progressFraction)
            .tint(colors.accent)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ForEach(store.progress.tasks) { task in
                taskRow(task)
            }
        }
    }

    private func taskRow(_ task: GettingStartedTask) -> some View {
        Button {
            guard !task.isComplete else { return }
            GettingStartedTaskNavigation.open(
                task: task.id,
                signals: store.signals,
                coordinator: navigationCoordinator
            )
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isComplete ? colors.profit : colors.secondaryText)
                    .font(.body)
                Text(task.label)
                    .experienceStyle(.subheadline, color: task.isComplete ? colors.secondaryText : colors.primaryText)
                    .strikethrough(task.isComplete, color: colors.secondaryText)
                Spacer(minLength: 0)
                if !task.isComplete {
                    ExperienceIcon(icon: .forward, size: .sm, color: colors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
        .disabled(task.isComplete)
        .accessibilityIdentifier("gettingStarted.task.\(task.id.rawValue)")
    }
}
