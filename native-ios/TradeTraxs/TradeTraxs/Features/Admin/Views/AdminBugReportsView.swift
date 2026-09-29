import SwiftUI

struct AdminBugReportsView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var viewModel: AdminBugReportsViewModel

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: AdminBugReportsViewModel(repository: data.adminBugReports)
        )
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                Picker("Status", selection: $viewModel.statusFilter) {
                    ForEach(AdminBugReportStatusFilter.allCases, id: \.self) { filter in
                        Text(filter.menuLabel).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.statusFilter) { _, _ in
                    Task { await viewModel.onFilterChanged() }
                }

                Picker("Severity", selection: $viewModel.severityFilter) {
                    ForEach(AdminBugReportSeverityFilter.allCases, id: \.self) { filter in
                        Text(filter.menuLabel).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.severityFilter) { _, _ in
                    Task { await viewModel.onFilterChanged() }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.reload() }
                    }
                }
            }

            Section {
                if viewModel.isLoading, viewModel.snapshots.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if viewModel.snapshots.isEmpty {
                    SettingsIntroBlock(
                        title: "No bug reports",
                        message: "Reports matching these filters will appear here."
                    )
                } else {
                    ForEach(viewModel.snapshots) { snapshot in
                        Button {
                            ExperienceHaptics.play(.selection)
                            navigationCoordinator.pushAdmin(.bugReportDetail(snapshot))
                        } label: {
                            AdminBugReportRowView(snapshot: snapshot)
                        }
                        .adminListRowInteraction()
                        .onAppear {
                            if snapshot.id == viewModel.snapshots.last?.id {
                                Task { await viewModel.loadMore() }
                            }
                        }
                    }
                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
        }
        .adminScreenHeading("Bug Reports")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
        .task {
            await viewModel.reload()
        }
        .accessibilityIdentifier("admin.bugReports")
    }
}

private struct AdminBugReportRowView: View {
    let snapshot: AdminBugReportSnapshot

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .top) {
                Text(snapshot.row.title)
                    .experienceStyle(.body, color: colors.primaryText)
                    .lineLimit(2)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    severityBadge
                    statusBadge
                }
            }
            Text(reporterLine)
                .experienceStyle(.caption, color: colors.secondaryText)
                .lineLimit(1)
            Text(BugReportDisplay.previewText(snapshot.row.description, max: 100))
                .experienceStyle(.caption, color: colors.tertiaryText)
                .lineLimit(2)
            HStack {
                if snapshot.row.screenshotURL != nil {
                    Text("Screenshot")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
                Spacer()
                if let created = snapshot.row.createdAt {
                    Text(created.formatted(date: .abbreviated, time: .shortened))
                        .experienceStyle(.caption, color: colors.tertiaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    private var reporterLine: String {
        BugReportDisplay.profileHandle(snapshot.reporter)
    }

    private var severityBadge: some View {
        Text(BugReportDisplay.severityShortLabel(snapshot.row.severity))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(severityColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var statusBadge: some View {
        Text(BugReportDisplay.statusLabel(snapshot.row.status))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(colors.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colors.surfaceSecondary)
            .clipShape(Capsule())
    }

    private var severityColor: Color {
        switch snapshot.row.severity {
        case .critical: return colors.loss
        case .high: return colors.warning
        case .medium: return colors.warning.opacity(0.85)
        case .low: return colors.tertiaryText
        }
    }
}

private extension AdminBugReportStatusFilter {
    var menuLabel: String {
        switch self {
        case .open: return "Open"
        case .in_progress: return "In progress"
        case .resolved: return "Resolved"
        case .all: return "All"
        }
    }
}

private extension AdminBugReportSeverityFilter {
    var menuLabel: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        case .all: return "All"
        }
    }
}
