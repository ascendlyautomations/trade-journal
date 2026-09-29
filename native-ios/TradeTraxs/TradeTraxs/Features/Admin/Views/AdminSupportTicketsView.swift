import SwiftUI

struct AdminSupportTicketsView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var viewModel: AdminSupportTicketsViewModel

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: AdminSupportTicketsViewModel(repository: data.adminSupportTickets)
        )
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                Picker("Queue", selection: $viewModel.queueFilter) {
                    ForEach(AdminSupportTicketQueueFilter.allCases, id: \.self) { filter in
                        Text(filter.menuLabel).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.queueFilter) { _, _ in
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
                        title: "No support tickets",
                        message: "Tickets in this queue will appear here."
                    )
                } else {
                    ForEach(viewModel.snapshots) { snapshot in
                        Button {
                            ExperienceHaptics.play(.selection)
                            navigationCoordinator.pushAdmin(.supportTicketDetail(snapshot))
                        } label: {
                            AdminSupportTicketRowView(snapshot: snapshot)
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
        .adminScreenHeading("Support")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
        .task {
            await viewModel.reload()
        }
        .accessibilityIdentifier("admin.support")
    }
}

private struct AdminSupportTicketRowView: View {
    let snapshot: AdminSupportTicketSnapshot

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .top) {
                Text(snapshot.row.subject)
                    .experienceStyle(.body, color: colors.primaryText)
                    .lineLimit(2)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    categoryBadge
                    statusBadge
                }
            }
            Text(reporterLine)
                .experienceStyle(.caption, color: colors.secondaryText)
                .lineLimit(1)
            Text(SupportTicketDisplay.previewText(snapshot.row.message, max: 100))
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
                if !snapshot.row.priority.isEmpty, snapshot.row.priority != "normal" {
                    Text(snapshot.row.priority.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.secondaryText)
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
        let email = snapshot.row.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let email, !email.isEmpty {
            return email
        }
        return SupportTicketDisplay.profileHandle(snapshot.submitter)
    }

    private var categoryBadge: some View {
        Text(SupportTicketDisplay.categoryLabel(snapshot.row.category))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(colors.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colors.surfaceSecondary)
            .clipShape(Capsule())
    }

    private var statusBadge: some View {
        Text(SupportTicketDisplay.statusLabel(snapshot.row.status))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(colors.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colors.surfaceSecondary)
            .clipShape(Capsule())
    }
}

private extension AdminSupportTicketQueueFilter {
    var menuLabel: String {
        switch self {
        case .unviewed: return "Unviewed"
        case .viewed: return "Viewed"
        case .open: return "Open"
        case .in_progress: return "In progress"
        case .resolved: return "Resolved"
        }
    }
}
