import SwiftUI

struct AdminProductFeedbackDetailView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var viewModel: AdminProductFeedbackDetailViewModel

    init(
        data: DataEnvironment,
        snapshot: AdminProductFeedbackSnapshot,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: AdminProductFeedbackDetailViewModel(
                snapshot: snapshot,
                repository: data.adminProductFeedback,
                adminUsers: data.adminUsers,
                session: data.session
            )
        )
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            feedbackSection
            userSection
            AdminSubmissionScreenshotSection(screenshotURL: viewModel.snapshot.row.screenshotURL)
            adminSection
        }
        .adminScreenHeading("Product Feedback")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
        .accessibilityIdentifier("admin.productFeedbackDetail")
    }

    private var feedbackSection: some View {
        Section("Feedback") {
            SettingsInfoRow(
                title: "Type",
                value: ProductFeedbackDisplay.typeLabel(viewModel.snapshot.row.parsedType)
            )
            if let title = viewModel.snapshot.row.parsedTitle, !title.isEmpty {
                SettingsInfoRow(title: "Title", value: title)
            }
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
            SettingsInfoRow(
                title: "Status",
                value: ProductFeedbackDisplay.statusLabel(viewModel.snapshot.row.status)
            )
        }
    }

    private var userSection: some View {
        Section("User") {
            if let submitter = viewModel.snapshot.submitter {
                SettingsInfoRow(title: "Name", value: ProductFeedbackDisplay.profileDisplayName(submitter))
                SettingsInfoRow(title: "Username", value: ProductFeedbackDisplay.profileHandle(submitter))
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

    private var adminSection: some View {
        Section("Admin") {
            Toggle("Mark as viewed", isOn: $viewModel.draftViewed)
            Picker("Status", selection: $viewModel.draftStatus) {
                ForEach(FeedbackSubmissionStatus.allCases, id: \.self) { status in
                    Text(ProductFeedbackDisplay.statusLabel(status)).tag(status)
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
