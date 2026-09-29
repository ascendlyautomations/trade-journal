import SwiftUI

struct AdminSupportTicketDetailView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var viewModel: AdminSupportTicketDetailViewModel

    init(
        data: DataEnvironment,
        snapshot: AdminSupportTicketSnapshot,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: AdminSupportTicketDetailViewModel(
                snapshot: snapshot,
                repository: data.adminSupportTickets,
                adminUsers: data.adminUsers,
                session: data.session
            )
        )
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            requestSection
            userSection
            statusSection
            AdminSubmissionScreenshotSection(screenshotURL: viewModel.snapshot.row.screenshotURL)
            adminSection
        }
        .adminScreenHeading("Support Ticket")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
        .accessibilityIdentifier("admin.supportTicketDetail")
    }

    private var requestSection: some View {
        Section("Support request") {
            SettingsInfoRow(title: "Subject", value: viewModel.snapshot.row.subject)
            SettingsInfoRow(
                title: "Category",
                value: SupportTicketDisplay.categoryLabel(viewModel.snapshot.row.category)
            )
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Message")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                Text(viewModel.snapshot.row.message.isEmpty ? "—" : viewModel.snapshot.row.message)
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

    private var userSection: some View {
        Section("User") {
            if let submitter = viewModel.snapshot.submitter {
                SettingsInfoRow(title: "Name", value: SupportTicketDisplay.profileDisplayName(submitter))
                SettingsInfoRow(title: "Username", value: SupportTicketDisplay.profileHandle(submitter))
            }
            if let email = viewModel.snapshot.row.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                SettingsInfoRow(title: "Email", value: email)
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

    private var statusSection: some View {
        Section("Status") {
            SettingsInfoRow(title: "Status", value: SupportTicketDisplay.statusLabel(viewModel.snapshot.row.status))
            SettingsInfoRow(title: "Priority", value: viewModel.snapshot.row.priority.capitalized)
            SettingsInfoRow(title: "Viewed", value: viewModel.snapshot.row.viewed ? "Yes" : "No")
        }
    }

    private var adminSection: some View {
        Section("Admin") {
            Toggle("Mark as viewed", isOn: $viewModel.draftViewed)
            Picker("Status", selection: $viewModel.draftStatus) {
                ForEach(SupportTicketStatus.allCases, id: \.self) { status in
                    Text(SupportTicketDisplay.statusLabel(status)).tag(status)
                }
            }
            TextField("Admin notes", text: $viewModel.draftAdminNotes, axis: .vertical)
                .lineLimit(3 ... 8)
            Button("Save") {
                Task { _ = await viewModel.saveReview() }
            }
            .disabled(!viewModel.canSave)
            if viewModel.saveBusy {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            if let message = viewModel.saveMessage {
                Text(message)
                    .experienceStyle(.footnote, color: colors.loss)
            }
        }
    }
}
