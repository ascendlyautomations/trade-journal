import SwiftUI

/// Single Manage Accounts experience — Settings, Dashboard, and Calendar all land here.
struct SettingsTradingAccountsView: View {
    @State private var viewModel: ManageAccountsViewModel
    @State private var editorPresentation: EditorPresentation?

    @Environment(\.themeColors) private var colors

    private let data: DataEnvironment?
    private let navigationCoordinator: NavigationCoordinator?

    private enum EditorPresentation: Identifiable {
        case create
        case edit(TradingAccount)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let account): return account.id.rawValue
            }
        }
    }

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator? = nil) {
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: ManageAccountsViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
        self.data = data
    }

    init(viewModel: ManageAccountsViewModel) {
        self.data = nil
        self.navigationCoordinator = nil
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.accounts.isEmpty {
                ManageAccountsFilterBar(viewModel: viewModel)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)
                    .padding(.bottom, ExperienceSpacing.xxs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            List {
            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            if let data {
                Section {
                    NavigationLink {
                        BrokerIntegrationsView(data: data)
                    } label: {
                        brokerIntegrationsRow
                    }
                    .accessibilityIdentifier("settings.tradingAccounts.brokerIntegrations")
                } header: {
                    Text("Broker Integrations")
                }
            }

            if viewModel.showsFilteredEmptyState {
                Section {
                    Text("Choose which accounts appear in account selectors throughout TradeTraxs.")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .lineLimit(3)
                        .listRowInsets(
                            EdgeInsets(
                                top: 0,
                                leading: ExperienceSpacing.md,
                                bottom: ExperienceSpacing.xxs,
                                trailing: ExperienceSpacing.md
                            )
                        )
                        .accessibilityIdentifier("manageAccounts.dropdownIntro")

                    SettingsIntroBlock(
                        title: "No matching accounts",
                        message: "Try changing your Prop Firm or Account Type filter."
                    )
                    Button("Clear Filters") {
                        viewModel.clearFilters()
                    }
                    .accessibilityIdentifier("manageAccounts.clearFilters")
                } header: {
                    Text("Your Accounts")
                }
            } else if viewModel.accounts.isEmpty, !viewModel.isLoading {
                Section {
                    SettingsIntroBlock(
                        title: "No trading accounts yet",
                        message: "Add an account to organize your trades by broker, prop firm, or backtest."
                    )
                } header: {
                    Text("Your Accounts")
                } footer: {
                    Text("Tap + to create your first account.")
                }
            } else {
                Section {
                    Text("Choose which accounts appear in account selectors throughout TradeTraxs.")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .lineLimit(3)
                        .listRowInsets(
                            EdgeInsets(
                                top: 0,
                                leading: ExperienceSpacing.md,
                                bottom: ExperienceSpacing.xxs,
                                trailing: ExperienceSpacing.md
                            )
                        )
                        .accessibilityIdentifier("manageAccounts.dropdownIntro")

                    ForEach(viewModel.filteredAccounts) { account in
                        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                            CompactAccountDropdownToggle(
                                isOn: Binding(
                                    get: { viewModel.showInAccountDropdowns(for: account.id) },
                                    set: { show in
                                        Task {
                                            await viewModel.setShowInAccountDropdowns(
                                                id: account.id,
                                                show: show
                                            )
                                        }
                                    }
                                ),
                                accessibilityIdentifier:
                                    "manageAccounts.showInDropdowns.\(account.id.rawValue)",
                                isOnAccessibilityValue: viewModel.showInAccountDropdowns(
                                    for: account.id
                                )
                            )

                            Button {
                                editorPresentation = .edit(account)
                            } label: {
                                HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                                        Text(viewModel.rowTitle(for: account))
                                            .experienceStyle(.body, color: colors.primaryText)
                                        Text(viewModel.rowSubtitle(for: account))
                                            .experienceStyle(.footnote, color: colors.secondaryText)
                                        if let note = account.note, !note.isEmpty {
                                            Text(note)
                                                .experienceStyle(.caption, color: colors.tertiaryText)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer(minLength: ExperienceSpacing.sm)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(colors.tertiaryText)
                                }
                                .padding(.vertical, ExperienceSpacing.xxs)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .accessibilityIdentifier("settings.account.\(account.id.rawValue)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                ExperienceHaptics.play(.selection)
                                Task {
                                    await viewModel.setActive(id: account.id, isActive: !account.isActive)
                                }
                            } label: {
                                Text(account.isActive ? "Deactivate" : "Activate")
                            }
                            .tint(account.isActive ? colors.secondaryText : colors.accent)
                        }
                        .contextMenu {
                            Button {
                                editorPresentation = .edit(account)
                            } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                            }
                            Button {
                                ExperienceHaptics.play(.selection)
                                Task {
                                    await viewModel.setActive(id: account.id, isActive: !account.isActive)
                                }
                            } label: {
                                Label(
                                    account.isActive ? "Deactivate" : "Activate",
                                    systemImage: account.isActive ? "pause.circle" : "checkmark.circle"
                                )
                            }
                        }
                    }
                } header: {
                    Text("Your Accounts")
                } footer: {
                    Text("Swipe to activate or deactivate. Deactivated accounts stay in history but hide from trade pickers.")
                }
            }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(ExperienceSpacing.xxs)
            .contentMargins(.top, viewModel.accounts.isEmpty ? ExperienceSpacing.xs : 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
        }
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Manage Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorPresentation = .create
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityIdentifier("manageAccounts.add")
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            NavigationStack {
                switch presentation {
                case .create:
                    ManageAccountEditorView(
                        viewModel: viewModel,
                        mode: .create,
                        draft: viewModel.emptyDraft(),
                        data: data,
                        navigationCoordinator: navigationCoordinator
                    )
                case .edit(let account):
                    ManageAccountEditorView(
                        viewModel: viewModel,
                        mode: .edit(account),
                        draft: viewModel.draft(from: account),
                        data: data,
                        navigationCoordinator: navigationCoordinator
                    )
                }
            }
            .experienceProtectedFormDismiss()
        }
        .onAppear { viewModel.loadIfNeeded() }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            Task { await viewModel.refresh() }
        }
        .accessibilityIdentifier("settings.tradingAccounts")
    }

    private var brokerIntegrationsRow: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Image(systemName: "link.circle")
                .font(.body.weight(.medium))
                .foregroundStyle(colors.accent)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Broker Integrations")
                    .experienceStyle(.body, color: colors.primaryText)
                Text("Connect & import trades")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Spacer(minLength: ExperienceSpacing.xs)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .contentShape(Rectangle())
    }
}
