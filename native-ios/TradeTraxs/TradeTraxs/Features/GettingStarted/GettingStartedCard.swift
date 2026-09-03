import SwiftUI

struct GettingStartedCard: View {
    @Bindable var store: GettingStartedStore
    let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            header
            if !store.isCollapsed {
                progressBar
                taskList
            }
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        )
        .accessibilityIdentifier("gettingStarted.card")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Getting Started")
                    .experienceStyle(.headline, color: colors.primaryText)
                Text("\(store.progress.completedCount) of \(store.progress.totalCount) complete")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Spacer()
            Button {
                ExperienceMotion.withAnimation(ExperienceMotion.selection, reduceMotion: reduceMotion) {
                    store.toggleCollapsed()
                }
            } label: {
                Image(systemName: store.isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(store.isCollapsed ? "Expand Getting Started" : "Collapse Getting Started")

            Button {
                store.dismissForSession()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss Getting Started for this session")
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
        .buttonStyle(.plain)
        .disabled(task.isComplete)
        .accessibilityIdentifier("gettingStarted.task.\(task.id.rawValue)")
    }
}
