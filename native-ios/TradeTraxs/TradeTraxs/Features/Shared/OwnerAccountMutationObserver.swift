import SwiftUI

extension View {
    /// Recomputes account dropdown options when owner account metadata changes (Manage Accounts save, etc.).
    func onOwnerAccountMutation(perform action: @escaping () -> Void) -> some View {
        onChange(of: AccountMutationStore.shared.revision) { _, _ in
            guard case .generic = AccountMutationStore.shared.latestKind else { return }
            action()
        }
    }
}