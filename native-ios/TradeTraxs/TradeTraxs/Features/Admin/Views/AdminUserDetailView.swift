import SwiftUI

struct AdminUserDetailView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var viewModel: AdminUserDetailViewModel
    @State private var confirmsBan = false
    @State private var confirmsUnban = false
    @State private var confirmsDelete = false
    init(data: DataEnvironment, user: AdminUserSummary, navigationCoordinator: NavigationCoordinator) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: AdminUserDetailViewModel(
                repository: data.adminUsers,
                session: data.session,
                user: user
            )
        )
    }

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            profileSection
            accountSection
            activitySection
            moderationSection
            dangerSection
        }
        .adminScreenHeading("User")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
        .task {
            await viewModel.loadActivity()
            if viewModel.deletePreview == nil, viewModel.deletePreviewError == nil {
                await viewModel.loadDeletePreview()
            }
        }
        .confirmationDialog("Ban this user?", isPresented: $confirmsBan, titleVisibility: .visible) {
            Button("Ban User", role: .destructive) {
                Task { _ = await viewModel.ban() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will lose access to TradeTraxs using the platform ban system.")
        }
        .confirmationDialog("Unban this user?", isPresented: $confirmsUnban, titleVisibility: .visible) {
            Button("Unban User") {
                Task { _ = await viewModel.unban() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Permanently delete this user?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                Task {
                    if await viewModel.deleteUser() {
                        navigationCoordinator.pop()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onChange(of: viewModel.didDelete) { _, deleted in
            if deleted { popToUsersList() }
        }
        .accessibilityIdentifier("admin.userDetail")
    }

    private var profileSection: some View {
        Section("Profile") {
            SettingsInfoRow(title: "Username", value: formattedUsername)
            if !viewModel.user.name.isEmpty {
                SettingsInfoRow(title: "Display name", value: viewModel.user.name)
            }
            SettingsInfoRow(title: "Email", value: viewModel.user.email)
            if let joined = viewModel.user.createdAt {
                SettingsInfoRow(title: "Joined", value: joined.formatted(date: .abbreviated, time: .omitted))
            }
            SettingsInfoRow(title: "User ID", value: viewModel.user.id.rawValue)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            SettingsInfoRow(
                title: "Status",
                value: viewModel.user.isBanned ? "Banned" : "Active"
            )
            if viewModel.user.isBanned, let reason = viewModel.user.bannedReason, !reason.isEmpty {
                SettingsInfoRow(title: "Ban reason", value: reason)
            }
            SettingsInfoRow(title: "Plan", value: viewModel.user.isPro ? "Pro" : "Free")
            if !viewModel.user.subscriptionStatus.isEmpty {
                SettingsInfoRow(title: "Subscription", value: viewModel.user.subscriptionStatus)
            }
            SettingsInfoRow(title: "Privacy", value: viewModel.user.isPrivate ? "Private" : "Public")
            if !viewModel.user.referralCode.isEmpty {
                SettingsInfoRow(title: "Referral code", value: viewModel.user.referralCode)
            }
            if viewModel.user.isBetaTester {
                SettingsInfoRow(title: "Beta tester", value: "Yes")
            }
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        Section("Activity") {
            if viewModel.isLoadingActivity {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let activity = viewModel.activity {
                SettingsInfoRow(title: "Trades", value: String(activity.trades))
                SettingsInfoRow(title: "Posts", value: String(activity.posts))
                SettingsInfoRow(title: "Achievements", value: String(activity.achievements))
                SettingsInfoRow(title: "Feedback", value: String(activity.feedback))
                SettingsInfoRow(title: "Support tickets", value: String(activity.supportTickets))
            } else if let error = viewModel.activityError {
                SettingsInlineError(message: error) {
                    Task { await viewModel.loadActivity() }
                }
            }
        }
    }

    private var moderationSection: some View {
        Section("Moderation") {
            if viewModel.user.isBanned {
                Button {
                    confirmsUnban = true
                } label: {
                    SettingsPrimaryActionLabel(title: "Unban User", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(viewModel.moderationBusy)
            } else {
                SettingsLabeledField(title: "Ban reason") {
                    TextField("Required for ban", text: $viewModel.banReason, axis: .vertical)
                        .lineLimit(2 ... 4)
                }
                Button {
                    confirmsBan = true
                } label: {
                    SettingsPrimaryActionLabel(title: "Ban User", systemImage: "nosign")
                }
                .disabled(viewModel.moderationBusy || viewModel.banReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message = viewModel.moderationMessage {
                Text(message)
                    .experienceStyle(.footnote, color: colors.loss)
            }
        }
    }

    private var dangerSection: some View {
        Section("Danger Zone") {
            if viewModel.isLoadingDeletePreview {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let preview = viewModel.deletePreview {
                ForEach(preview.fields, id: \.label) { field in
                    SettingsInfoRow(title: field.label, value: field.value)
                }
            } else if let error = viewModel.deletePreviewError {
                SettingsInlineError(message: error) {
                    Task { await viewModel.loadDeletePreview() }
                }
            }

            SettingsLabeledField(title: "Confirmation", helper: "Type DELETE to enable permanent deletion.") {
                TextField("DELETE", text: $viewModel.deleteConfirmText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            Button(role: .destructive) {
                confirmsDelete = true
            } label: {
                SettingsNavigationRow(
                    title: viewModel.deleteBusy ? "Deleting…" : "Delete User Permanently",
                    systemImage: "trash",
                    isDestructive: true,
                    showsChevron: false
                )
            }
            .disabled(viewModel.deleteBusy || viewModel.deleteConfirmText != "DELETE")

            if let deleteError = viewModel.deleteError {
                Text(deleteError)
                    .experienceStyle(.footnote, color: colors.loss)
            }
        }
    }

    private var formattedUsername: String {
        let u = viewModel.user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return "—" }
        return u.hasPrefix("@") ? u : "@\(u)"
    }

    private func popToUsersList() {
        navigationCoordinator.pop()
    }
}
