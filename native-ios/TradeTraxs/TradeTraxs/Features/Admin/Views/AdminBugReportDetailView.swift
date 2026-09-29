import SwiftUI

struct AdminBugReportDetailView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var viewModel: AdminBugReportDetailViewModel

    init(
        data: DataEnvironment,
        snapshot: AdminBugReportSnapshot,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: AdminBugReportDetailViewModel(
                snapshot: snapshot,
                repository: data.adminBugReports,
                adminUsers: data.adminUsers
            )
        )
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            bugSection
            reporterSection
            triageSection
            environmentSection
            AdminSubmissionScreenshotSection(screenshotURL: viewModel.snapshot.row.screenshotURL)
            statusSection
        }
        .adminScreenHeading("Bug Report")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
        .accessibilityIdentifier("admin.bugReportDetail")
    }

    private var bugSection: some View {
        Section("Bug") {
            SettingsInfoRow(title: "Title", value: viewModel.snapshot.row.title)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Description")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                Text(viewModel.snapshot.row.description.isEmpty ? "—" : viewModel.snapshot.row.description)
                    .experienceStyle(.body, color: colors.primaryText)
            }
            if let created = viewModel.snapshot.row.createdAt {
                SettingsInfoRow(
                    title: "Submitted",
                    value: created.formatted(date: .abbreviated, time: .shortened)
                )
            }
        }
    }

    private var reporterSection: some View {
        Section("Reporter") {
            if let reporter = viewModel.snapshot.reporter {
                SettingsInfoRow(title: "Name", value: BugReportDisplay.profileDisplayName(reporter))
                SettingsInfoRow(title: "Username", value: BugReportDisplay.profileHandle(reporter))
            }
            SettingsInfoRow(title: "User ID", value: viewModel.snapshot.row.userID.rawValue)
            Button("Open User") {
                Task {
                    if let user = await viewModel.fetchUserForNavigation() {
                        navigationCoordinator.pushAdmin(.userDetail(user))
                    }
                }
            }
            .disabled(viewModel.openUserBusy)
            if let error = viewModel.openUserError {
                Text(error)
                    .experienceStyle(.footnote, color: colors.loss)
            }
        }
    }

    private var triageSection: some View {
        Section("Triage") {
            SettingsInfoRow(
                title: "Severity",
                value: BugReportDisplay.severityLabel(viewModel.snapshot.row.severity)
            )
            SettingsInfoRow(
                title: "Status",
                value: BugReportDisplay.statusLabel(viewModel.snapshot.row.status)
            )
            if let resolved = viewModel.snapshot.row.resolvedAt {
                SettingsInfoRow(
                    title: "Resolved",
                    value: resolved.formatted(date: .abbreviated, time: .shortened)
                )
            }
        }
    }

    private var environmentSection: some View {
        Section("Environment") {
            SettingsInfoRow(
                title: BugReportDisplay.environmentContextLabel(pageURL: viewModel.snapshot.row.pageURL),
                value: viewModel.snapshot.row.pageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (viewModel.snapshot.row.pageURL ?? "—")
                    : "—"
            )
            SettingsInfoRow(
                title: BugReportDisplay.environmentClientLabel(browserInfo: viewModel.snapshot.row.browserInfo),
                value: viewModel.snapshot.row.browserInfo?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (viewModel.snapshot.row.browserInfo ?? "—")
                    : "—"
            )
        }
    }

    private var statusSection: some View {
        Section("Update status") {
            if viewModel.snapshot.row.status != .resolved {
                Button("Mark resolved") {
                    Task { _ = await viewModel.markResolved() }
                }
                .disabled(viewModel.statusBusy)
            }
            Picker("Status", selection: $viewModel.draftStatus) {
                ForEach(BugReportStatus.allCases, id: \.self) { status in
                    Text(BugReportDisplay.statusLabel(status)).tag(status)
                }
            }
            Button("Save status") {
                Task { _ = await viewModel.saveStatus() }
            }
            .disabled(!viewModel.canSaveStatus)
            if viewModel.statusBusy {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            if let message = viewModel.statusMessage {
                Text(message)
                    .experienceStyle(.footnote, color: colors.loss)
            }
        }
    }
}
