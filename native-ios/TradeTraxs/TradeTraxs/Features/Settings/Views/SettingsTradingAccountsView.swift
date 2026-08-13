import SwiftUI

/// Single Manage Accounts experience — Settings, Dashboard, and Calendar all land here.
struct SettingsTradingAccountsView: View {
    @State private var viewModel: ManageAccountsViewModel
    var propFirmOnly: Bool = false

    @State private var editorPresentation: EditorPresentation?
    @Environment(\.themeColors) private var colors

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

    init(data: DataEnvironment, propFirmOnly: Bool = false) {
        _viewModel = State(
            initialValue: ManageAccountsViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
        self.propFirmOnly = propFirmOnly
    }

    init(viewModel: ManageAccountsViewModel, propFirmOnly: Bool = false) {
        _viewModel = State(initialValue: viewModel)
        self.propFirmOnly = propFirmOnly
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            let rows = propFirmOnly ? viewModel.propAccounts : viewModel.accounts
            if rows.isEmpty, !viewModel.isLoading {
                Section {
                    Text(propFirmOnly ? "No prop firm accounts yet." : "No trading accounts yet.")
                        .experienceStyle(.body, color: colors.secondaryText)
                }
            } else {
                Section {
                    ForEach(rows) { account in
                        Button {
                            editorPresentation = .edit(account)
                        } label: {
                            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(TradingAccountDisplay.title(for: account, audience: .owner))
                                        .experienceStyle(.body, color: colors.primaryText)
                                    Text(viewModel.subtitle(for: account))
                                        .experienceStyle(.footnote, color: colors.secondaryText)
                                    if let note = account.note, !note.isEmpty {
                                        Text(note)
                                            .experienceStyle(.caption, color: colors.tertiaryText)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(colors.tertiaryText)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.account.\(account.id.rawValue)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task {
                                    await viewModel.setActive(id: account.id, isActive: !account.isActive)
                                }
                            } label: {
                                Text(account.isActive ? "Deactivate" : "Activate")
                            }
                            .tint(account.isActive ? colors.secondaryText : colors.accent)
                        }
                    }
                } footer: {
                    Text("Deactivate hides an account from trade pickers but keeps its history. Accounts are never deleted.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle(propFirmOnly ? "Prop Firm" : "Manage Accounts")
        .toolbar {
            if !propFirmOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorPresentation = .create
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .accessibilityIdentifier("manageAccounts.add")
                }
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
                        draft: viewModel.emptyDraft()
                    )
                case .edit(let account):
                    ManageAccountEditorView(
                        viewModel: viewModel,
                        mode: .edit(account.id),
                        draft: viewModel.draft(from: account)
                    )
                }
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier(propFirmOnly ? "settings.propFirm" : "settings.tradingAccounts")
    }
}
