import SwiftUI

/// Create-account sheet — same presentation as ``SettingsTradingAccountsView`` editor `.create`` branch.
struct ManageAccountCreateAccountSheet: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator?

    @State private var viewModel: ManageAccountsViewModel

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator? = nil) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: ManageAccountsViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
    }

    var body: some View {
        NavigationStack {
            ManageAccountEditorView(
                viewModel: viewModel,
                mode: .create,
                draft: viewModel.emptyDraft(),
                data: data,
                navigationCoordinator: navigationCoordinator
            )
        }
        .experienceProtectedFormDismiss()
        .onAppear { viewModel.loadIfNeeded() }
    }
}
