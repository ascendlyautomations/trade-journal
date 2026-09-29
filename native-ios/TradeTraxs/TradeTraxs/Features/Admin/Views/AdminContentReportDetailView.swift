import SwiftUI

struct AdminContentReportDetailView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator
    let currentUserProfile: CurrentUserProfileStore?

    @State private var viewModel: AdminContentReportDetailViewModel
    @State private var confirmsBan = false
    @State private var confirmsUnban = false

    init(
        data: DataEnvironment,
        snapshot: AdminContentReportSnapshot,
        navigationCoordinator: NavigationCoordinator,
        currentUserProfile: CurrentUserProfileStore?
    ) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        self.currentUserProfile = currentUserProfile
        _viewModel = State(
            initialValue: AdminContentReportDetailViewModel(
                snapshot: snapshot,
                reportsRepository: data.adminContentReports,
                adminUsers: data.adminUsers,
                session: data.session
            )
        )
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            reportSection
            reportedContentSection
            reporterSection
            if viewModel.reportedUserID != nil {
                moderationSection
            }
            statusSection
        }
        .adminScreenHeading("Report")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
        .confirmationDialog("Ban this user?", isPresented: $confirmsBan, titleVisibility: .visible) {
            Button("Ban User", role: .destructive) {
                Task { _ = await viewModel.banReportedUser() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will lose access to TradeTraxs using the platform ban system.")
        }
        .confirmationDialog("Unban this user?", isPresented: $confirmsUnban, titleVisibility: .visible) {
            Button("Unban User") {
                Task { _ = await viewModel.unbanReportedUser() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("admin.contentReportDetail")
    }

    private var reportSection: some View {
        Section("Report") {
            SettingsInfoRow(
                title: "Reason",
                value: ContentReportDisplay.reasonLabel(viewModel.snapshot.row.reason)
            )
            if let details = viewModel.snapshot.row.details?.trimmingCharacters(in: .whitespacesAndNewlines),
               !details.isEmpty {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text("Details")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                    Text(details)
                        .experienceStyle(.body, color: colors.primaryText)
                }
            }
            if let created = viewModel.snapshot.row.createdAt {
                SettingsInfoRow(title: "Submitted", value: created.formatted(date: .abbreviated, time: .shortened))
            }
            SettingsInfoRow(
                title: "Status",
                value: ContentReportDisplay.statusLabel(viewModel.snapshot.row.status)
            )
            if let reviewed = viewModel.snapshot.row.reviewedAt {
                SettingsInfoRow(title: "Reviewed", value: reviewed.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private var reportedContentSection: some View {
        Section(viewModel.snapshot.row.targetType == .user ? "Reported profile" : "Reported content") {
            SettingsInfoRow(
                title: "Type",
                value: ContentReportDisplay.targetLabel(viewModel.snapshot.row.targetType)
            )
            SettingsInfoRow(title: "Preview", value: viewModel.snapshot.targetPreview.headline)
            if let subline = viewModel.snapshot.targetPreview.subline, !subline.isEmpty {
                SettingsInfoRow(title: "Context", value: subline)
            }
            if viewModel.snapshot.targetPreview.unavailable {
                Text("Original content may have been deleted.")
                    .experienceStyle(.footnote, color: colors.warning)
            }
            if let owner = viewModel.snapshot.targetPreview.ownerUserID,
               let profile = viewModel.snapshot.reportedUser ?? profileFor(owner) {
                SettingsInfoRow(title: "Author", value: ContentReportDisplay.profileDisplayName(profile))
            }
            openContentButton
        }
    }

    @ViewBuilder
    private var openContentButton: some View {
        if let destination = viewModel.snapshot.targetPreview.openDestination {
            Button(openLabel(for: destination)) {
                ExperienceHaptics.play(.selection)
                appendInspectRoute(destination)
            }
            .disabled(viewModel.snapshot.targetPreview.unavailable)
        } else if viewModel.snapshot.row.targetType == .user {
            Button("View Profile") {
                ExperienceHaptics.play(.selection)
                navigationCoordinator.pushAdmin(.inspectProfile(ProfileID(viewModel.snapshot.row.targetID)))
            }
        }
    }

    private var reporterSection: some View {
        Section("Reporter") {
            if let reporter = viewModel.snapshot.reporter {
                SettingsInfoRow(title: "Name", value: ContentReportDisplay.profileDisplayName(reporter))
                SettingsInfoRow(title: "Username", value: ContentReportDisplay.profileHandle(reporter))
            } else {
                SettingsInfoRow(title: "Reporter", value: "Profile unavailable")
            }
        }
    }

    private var moderationSection: some View {
        Section("Moderation") {
            if let reported = viewModel.snapshot.reportedUser {
                SettingsInfoRow(
                    title: "Reported user",
                    value: ContentReportDisplay.profileHandle(reported)
                )
                SettingsInfoRow(
                    title: "Account",
                    value: reported.isBanned ? "Banned" : "Active"
                )
            }
            if viewModel.reportedUserIsBanned {
                Button("Unban User") {
                    confirmsUnban = true
                }
                .disabled(viewModel.moderationBusy)
            } else {
                TextField("Ban reason", text: $viewModel.banReason, axis: .vertical)
                    .lineLimit(2...4)
                Button("Ban User", role: .destructive) {
                    confirmsBan = true
                }
                .disabled(viewModel.moderationBusy || viewModel.banReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message = viewModel.moderationMessage {
                Text(message)
                    .experienceStyle(.footnote, color: colors.loss)
            }
        }
    }

    private var statusSection: some View {
        Section("Update status") {
            Picker("Status", selection: $viewModel.draftStatus) {
                ForEach(ContentReportStatus.allCases, id: \.self) { status in
                    Text(ContentReportDisplay.statusLabel(status)).tag(status)
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

    private func profileFor(_ id: ProfileID) -> AdminReportProfileSummary? {
        viewModel.snapshot.reportedUser?.id == id ? viewModel.snapshot.reportedUser : nil
    }

    private func openLabel(for destination: AdminReportOpenDestination) -> String {
        switch destination {
        case .profile: return "View Profile"
        default: return "View Content"
        }
    }

    private func appendInspectRoute(_ destination: AdminReportOpenDestination) {
        switch destination {
        case .trade(let id): navigationCoordinator.pushAdmin(.inspectTrade(id))
        case .post(let id): navigationCoordinator.pushAdmin(.inspectPost(id))
        case .reel(let id): navigationCoordinator.pushAdmin(.inspectReel(id))
        case .achievement(let id): navigationCoordinator.pushAdmin(.inspectAchievement(id))
        case .profile(let id): navigationCoordinator.pushAdmin(.inspectProfile(id))
        case .room(let id): navigationCoordinator.pushAdmin(.inspectRoom(id))
        }
    }
}
