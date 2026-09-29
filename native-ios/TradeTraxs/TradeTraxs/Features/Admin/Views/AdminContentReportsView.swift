import SwiftUI

struct AdminContentReportsView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var viewModel: AdminContentReportsViewModel

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: AdminContentReportsViewModel(repository: data.adminContentReports)
        )
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                Picker("Status", selection: $viewModel.statusFilter) {
                    ForEach(AdminContentReportStatusFilter.allCases, id: \.self) { filter in
                        Text(filter.menuLabel).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.statusFilter) { _, _ in
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
                        title: viewModel.emptyTitle(),
                        message: "Reports matching this filter will appear here."
                    )
                } else {
                    ForEach(viewModel.snapshots) { snapshot in
                        Button {
                            ExperienceHaptics.play(.selection)
                            navigationCoordinator.pushAdmin(.contentReportDetail(snapshot))
                        } label: {
                            AdminContentReportRowView(snapshot: snapshot)
                        }
                        .adminListRowInteraction()
                        .onAppear {
                            if snapshot.row.id == viewModel.snapshots.last?.row.id {
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
        .adminScreenHeading("Content Reports")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
        .task {
            await viewModel.reload()
        }
        .accessibilityIdentifier("admin.contentReports")
    }
}

private struct AdminContentReportRowView: View {
    let snapshot: AdminContentReportSnapshot

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack {
                Text(ContentReportDisplay.reasonLabel(snapshot.row.reason))
                    .experienceStyle(.body, color: colors.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(ContentReportDisplay.statusLabel(snapshot.row.status))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            Text(subjectLine)
                .experienceStyle(.footnote, color: colors.secondaryText)
                .lineLimit(2)
            if let preview = compactPreview {
                Text(preview)
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .lineLimit(2)
            }
            HStack {
                if let created = snapshot.row.createdAt {
                    Text(created.formatted(date: .abbreviated, time: .shortened))
                        .experienceStyle(.caption, color: colors.tertiaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    private var subjectLine: String {
        let reporter = ContentReportDisplay.profileHandle(snapshot.reporter)
        let subject = AdminContentReportHydration.listReportedSubjectLabel(
            row: snapshot.row,
            enrichment: AdminContentReportEnrichment(
                profiles: buildProfileMap(),
                targets: [targetKey: snapshot.targetPreview]
            )
        )
        return "\(subject) · reported by \(reporter)"
    }

    private var compactPreview: String? {
        let headline = snapshot.targetPreview.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headline.isEmpty, snapshot.row.targetType != .user else { return nil }
        return headline
    }

    private var targetKey: String {
        "\(snapshot.row.targetType.rawValue):\(snapshot.row.targetID)"
    }

    private func buildProfileMap() -> [ProfileID: AdminReportProfileSummary] {
        var map: [ProfileID: AdminReportProfileSummary] = [:]
        if let reporter = snapshot.reporter { map[reporter.id] = reporter }
        if let reported = snapshot.reportedUser { map[reported.id] = reported }
        return map
    }

    private var statusColor: Color {
        switch snapshot.row.status {
        case .open: return colors.loss
        case .reviewing: return colors.warning
        case .resolved: return colors.profit
        case .dismissed: return colors.tertiaryText
        }
    }
}

private extension AdminContentReportStatusFilter {
    var menuLabel: String {
        switch self {
        case .open: return "Open"
        case .reviewing: return "Reviewing"
        case .resolved: return "Resolved"
        case .dismissed: return "Dismissed"
        case .all: return "All"
        }
    }
}
