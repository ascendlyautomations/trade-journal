import SwiftUI

struct CopyTradingAccountsView: View {
    @State private var viewModel: CopyTradingAccountsViewModel

    @Environment(\.themeColors) private var colors

    init(data: DataEnvironment) {
        _viewModel = State(
            initialValue: CopyTradingAccountsViewModel(
                groupsRepository: DefaultCopyTradingGroupRepository(
                    supabase: data.supabase,
                    session: data.session
                ),
                trades: data.trades,
                session: data.session
            )
        )
    }

    init(viewModel: CopyTradingAccountsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let billing = SessionBillingEntitlementStore.shared.status
        List {
            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                    .experienceDashboardListRow()
                }
            }

            if viewModel.groups.isEmpty, !viewModel.isLoading {
                Section {
                    ExperienceEmptyState(
                        title: "No copy trading groups yet",
                        message: "Create a group to journal the same trade across multiple accounts."
                    )
                    .experienceDashboardListRow()
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Existing Groups")
                }
            } else if !viewModel.groups.isEmpty {
                Section {
                    ForEach(viewModel.groups) { group in
                        Button {
                            viewModel.beginEdit(group)
                        } label: {
                            groupRow(group)
                        }
                        .buttonStyle(.plain)
                        .experienceDashboardListRow()
                        .accessibilityIdentifier("copyTrading.group.\(group.id)")
                    }
                } header: {
                    Text("Existing Groups")
                }
            }

            Section {
                Button {
                    viewModel.beginCreate()
                } label: {
                    HStack(spacing: ExperienceSpacing.sm) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(colors.accent)
                            .accessibilityHidden(true)
                        Text("Create Copy Trading Group")
                            .experienceStyle(.body, color: colors.primaryText)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .experienceDashboardListRow()
                .accessibilityIdentifier("copyTrading.create")
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .listSectionSpacing(ExperienceSpacing.xxs)
        .contentMargins(.top, ExperienceSpacing.xxs, for: .scrollContent)
        .experienceNavigationTitle("Copy Trading Accounts")
        .proUpgradeSheet()
        .task {
            let isPro = billing?.hasTraxProAccess == true
            _ = ProUpgradeCoordinator.shared.presentIfNeeded(isPro: isPro, feature: .copyTrading)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .sheet(item: $viewModel.editor) { _ in
            NavigationStack {
                CopyTradingGroupEditorView(viewModel: viewModel)
            }
            .experienceProtectedFormDismiss()
            .experienceSheetChrome()
        }
        .confirmationDialog(
            "Delete copy trading group?",
            isPresented: Binding(
                get: { viewModel.pendingDelete != nil },
                set: { isPresented in
                    if !isPresented { viewModel.pendingDelete = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDelete = nil
            }
        } message: {
            Text("Deleting this Copy Trading Group will unlink the accounts from the group. Your trading accounts and historical trades will not be deleted.")
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.copyTradingAccounts")
    }

    private func groupRow(_ group: CopyTradingGroup) -> some View {
        let linked = viewModel.linkedAccounts(for: group)
        let count = linked.isEmpty ? group.accountIDs.count : linked.count
        return VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name)
                    .experienceStyle(.body, color: colors.primaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            Text("\(count) linked account\(count == 1 ? "" : "s")")
                .experienceStyle(.footnote, color: colors.secondaryText)
            if linked.isEmpty {
                Text("No linked accounts. Edit this group to add accounts.")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            } else {
                ForEach(linked) { account in
                    Text(account.name)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct CopyTradingGroupEditorView: View {
    @Bindable var viewModel: CopyTradingAccountsViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var body: some View {
        Form {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .experienceStyle(.footnote, color: colors.loss)
                        .addCopyTradingFormRow()
                }
            }
            Section {
                TextField("Group Name", text: nameBinding)
                    .textInputAutocapitalization(.words)
                    .addCopyTradingFormRow()
                    .accessibilityIdentifier("copyTrading.groupName")
            } footer: {
                Text("Journal the same trade across these accounts.")
            }

            Section {
                if viewModel.selectableAccounts.isEmpty {
                    Text("Create trading accounts first, then link them to a copy group.")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .addCopyTradingFormRow()
                } else {
                    ForEach(viewModel.selectableAccounts) { account in
                        let selected = viewModel.editor?.selectedAccountIDs.contains(account.id.rawValue) == true
                        Button {
                            viewModel.toggleAccount(account.id.rawValue)
                        } label: {
                            HStack(spacing: ExperienceSpacing.sm) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? colors.accent : colors.tertiaryText)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .experienceStyle(.body, color: colors.primaryText)
                                    Text(account.isActive ? "Active" : "Inactive")
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .addCopyTradingFormRow()
                        .accessibilityIdentifier("copyTrading.account.\(account.id.rawValue)")
                    }
                }
            } header: {
                Text("Accounts")
            } footer: {
                Text("Select at least two accounts you own.")
            }

            if viewModel.editor?.groupID != nil, let group = currentGroup {
                Section {
                    Button("Delete Group", role: .destructive) {
                        viewModel.pendingDelete = group
                        dismiss()
                    }
                    .addCopyTradingFormRow()
                    .accessibilityIdentifier("copyTrading.delete")
                }
            }
        }
        .experienceTradeTraxsFormStyle(pageBackground: true)
        .experienceNavigationTitle(viewModel.editor?.groupID == nil ? "Create Group" : "Edit Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(viewModel.isSaving ? "Saving…" : "Save") {
                    Task {
                        if await viewModel.saveEditor() {
                            dismiss()
                        }
                    }
                }
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("copyTrading.save")
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { viewModel.editor?.name ?? "" },
            set: { newValue in
                viewModel.editor?.name = newValue
            }
        )
    }

    private var currentGroup: CopyTradingGroup? {
        guard let id = viewModel.editor?.groupID else { return nil }
        return viewModel.groups.first(where: { $0.id == id })
    }
}

private extension View {
    func addCopyTradingFormRow() -> some View {
        experienceDashboardListRow()
            .listRowInsets(
                EdgeInsets(
                    top: ExperienceSpacing.xxs,
                    leading: ExperienceSpacing.md,
                    bottom: ExperienceSpacing.xxs,
                    trailing: ExperienceSpacing.md
                )
            )
    }
}
