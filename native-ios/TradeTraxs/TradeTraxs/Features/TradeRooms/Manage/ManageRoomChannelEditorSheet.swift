import SwiftUI

struct ManageRoomChannelEditorSheet: View {
    let channel: RoomChannel?
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: (String, Bool) -> Void

    @Environment(\.themeColors) private var colors
    @State private var name: String
    @State private var allowMembersChat: Bool
    @State private var showsDiscardConfirm = false

    init(
        channel: RoomChannel?,
        isSaving: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, Bool) -> Void
    ) {
        self.channel = channel
        self.isSaving = isSaving
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: channel?.name ?? "")
        _allowMembersChat = State(initialValue: channel?.allowMembersChat ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Channel Name") {
                    TextField("Channel name", text: $name)
                        .textInputAutocapitalization(.never)
                }
                Section("Permissions") {
                    Toggle("Members can chat", isOn: $allowMembersChat)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .experienceScreenBackground()
            .experienceNavigationTitle(channel == nil ? "New Channel" : "Edit Channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges {
                            showsDiscardConfirm = true
                        } else {
                            onCancel()
                        }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, allowMembersChat)
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showsDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive, action: onCancel)
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .presentationDetents([.medium])
        .experienceProtectedFormDismiss()
    }

    private var hasChanges: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if channel == nil {
            return !trimmed.isEmpty || !allowMembersChat
        }
        return trimmed != channel?.name || allowMembersChat != channel?.allowMembersChat
    }
}
