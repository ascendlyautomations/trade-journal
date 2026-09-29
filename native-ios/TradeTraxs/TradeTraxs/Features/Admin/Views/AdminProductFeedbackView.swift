import SwiftUI

struct AdminProductFeedbackView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var viewModel: AdminProductFeedbackViewModel

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: AdminProductFeedbackViewModel(repository: data.adminProductFeedback)
        )
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                Picker("Queue", selection: $viewModel.queueFilter) {
                    ForEach(AdminProductFeedbackQueueFilter.allCases, id: \.self) { filter in
                        Text(filter.menuLabel).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.queueFilter) { _, _ in
                    Task { await viewModel.onFilterChanged() }
                }

                Picker("Type", selection: $viewModel.typeFilter) {
                    ForEach(AdminProductFeedbackTypeFilter.allCases, id: \.self) { filter in
                        Text(filter.menuLabel).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.typeFilter) { _, _ in
                    Task { await viewModel.onFilterChanged() }
                }

                Picker("Status", selection: $viewModel.statusFilter) {
                    ForEach(AdminProductFeedbackStatusFilter.allCases, id: \.self) { filter in
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
                        title: "No feedback",
                        message: "Submissions matching these filters will appear here."
                    )
                } else {
                    ForEach(viewModel.snapshots) { snapshot in
                        Button {
                            ExperienceHaptics.play(.selection)
                            navigationCoordinator.pushAdmin(.productFeedbackDetail(snapshot))
                        } label: {
                            AdminProductFeedbackRowView(snapshot: snapshot)
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
        .adminScreenHeading("Product Feedback")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
        .task {
            await viewModel.reload()
        }
        .accessibilityIdentifier("admin.productFeedback")
    }
}

private struct AdminProductFeedbackRowView: View {
    let snapshot: AdminProductFeedbackSnapshot

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(typeLine)
                        .experienceStyle(.body, color: colors.primaryText)
                        .lineLimit(1)
                    if let title = snapshot.row.parsedTitle, !title.isEmpty {
                        Text(title)
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                statusBadge
            }
            Text(reporterLine)
                .experienceStyle(.caption, color: colors.secondaryText)
                .lineLimit(1)
            Text(ProductFeedbackDisplay.previewText(snapshot.row.message, max: 100))
                .experienceStyle(.caption, color: colors.tertiaryText)
                .lineLimit(2)
            HStack {
                if !snapshot.row.viewed {
                    Text("Unviewed")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
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

    private var typeLine: String {
        if let type = snapshot.row.parsedType {
            return ProductFeedbackDisplay.typeLabel(type)
        }
        return snapshot.row.rawSubject ?? "Feedback"
    }

    private var reporterLine: String {
        let email = snapshot.row.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let email, !email.isEmpty {
            return email
        }
        return ProductFeedbackDisplay.profileHandle(snapshot.submitter)
    }

    private var statusBadge: some View {
        Text(ProductFeedbackDisplay.statusLabel(snapshot.row.status))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(colors.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colors.surfaceSecondary)
            .clipShape(Capsule())
    }
}

private extension AdminProductFeedbackQueueFilter {
    var menuLabel: String {
        switch self {
        case .unviewed: return "Unviewed"
        case .viewed: return "Viewed"
        }
    }
}

private extension AdminProductFeedbackTypeFilter {
    var menuLabel: String {
        switch self {
        case .all: return "All types"
        case .featureRequest: return "Feature Request"
        case .improvement: return "Improvement"
        case .bug: return "Bug"
        case .other: return "Other"
        }
    }
}

private extension AdminProductFeedbackStatusFilter {
    var menuLabel: String {
        switch self {
        case .all: return "All statuses"
        case .open: return "Open"
        case .planned: return "Planned"
        case .in_progress: return "In progress"
        case .resolved: return "Resolved"
        }
    }
}
