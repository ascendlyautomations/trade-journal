import SwiftUI

struct AdminUsersView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var viewModel: AdminUsersViewModel

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: AdminUsersViewModel(repository: data.adminUsers)
        )
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                TextField("Search username, email, name…", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.searchText) { _, _ in
                        viewModel.onSearchChanged()
                    }

                Picker("Status", selection: $viewModel.bannedFilter) {
                    ForEach(AdminUserBannedFilter.allCases, id: \.self) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.bannedFilter) { _, _ in
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
                if viewModel.isLoading, viewModel.rows.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if viewModel.rows.isEmpty {
                    SettingsIntroBlock(
                        title: "No users found",
                        message: "Try a different search or filter."
                    )
                } else {
                    ForEach(viewModel.rows) { row in
                        Button {
                            ExperienceHaptics.play(.selection)
                            navigationCoordinator.pushAdmin(.userDetail(row))
                        } label: {
                            AdminUserRow(summary: row)
                        }
                        .adminListRowInteraction()
                        .onAppear {
                            if row.id == viewModel.rows.last?.id {
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
            } footer: {
                if viewModel.total > 0 {
                    Text("\(viewModel.rows.count) of \(viewModel.total) users")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                }
            }
        }
        .adminScreenHeading("Users")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
        .task {
            await viewModel.reload()
        }
        .accessibilityIdentifier("admin.users")
    }
}

private struct AdminUserRow: View {
    let summary: AdminUserSummary

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                HStack(spacing: ExperienceSpacing.xxs) {
                    Text(displayHandle)
                        .experienceStyle(.body, color: colors.primaryText)
                        .lineLimit(1)
                    if summary.isHiddenFromCommunity {
                        Text("Hidden")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(colors.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colors.warning.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if summary.isBanned {
                        Text("Banned")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(colors.loss)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colors.loss.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                if !summary.name.isEmpty, summary.name != summary.username {
                    Text(summary.name)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .lineLimit(1)
                }
                Text(summary.email)
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.tertiaryText)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    private var displayHandle: String {
        let u = summary.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty { return u.hasPrefix("@") ? u : "@\(u)" }
        return summary.email.isEmpty ? summary.id.rawValue.prefix(8).description : summary.email
    }
}

private extension AdminUserBannedFilter {
    var label: String {
        switch self {
        case .all: return "All"
        case .banned: return "Banned"
        case .active: return "Active"
        }
    }
}
