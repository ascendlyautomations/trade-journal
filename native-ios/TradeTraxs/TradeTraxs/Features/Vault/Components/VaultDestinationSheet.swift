import SwiftUI

/// Compact Add/Manage Vault sheet — Quick Save, folders, and removal.
struct VaultDestinationSheet: View {
    let ref: VaultContentRef
    @Bindable var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    @State private var newFolderName = ""
    @State private var showsNewFolderField = false
    @State private var inFlight = false

    private var snap: VaultItemState { store.state(for: ref) }

    var body: some View {
        NavigationStack {
            List {
                if snap.isVaulted {
                    manageSection
                } else {
                    addSection
                }

                foldersSection

                if showsNewFolderField {
                    newFolderSection
                }
            }
            .navigationTitle(snap.isVaulted ? "Manage in Vault" : "Add to Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                store.loadFoldersIfNeeded()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var addSection: some View {
        Section {
            Button {
                perform {
                    let ok = await store.quickSave(ref)
                    if ok { dismiss() }
                }
            } label: {
                Label("Quick Save", systemImage: "hexagon.fill")
            }
            .disabled(inFlight)
        } footer: {
            Text("Saves to your Vault without choosing a folder.")
        }
    }

    private var manageSection: some View {
        Section("In Vault") {
            if snap.folderIDs.isEmpty {
                Text("Quick Save")
                    .experienceStyle(.body, color: colors.secondaryText)
            } else {
                ForEach(membershipFolders, id: \.id) { folder in
                    HStack {
                        Text(folder.name)
                        Spacer()
                        Button("Remove") {
                            perform {
                                _ = await store.removeFromFolder(ref, folderID: folder.id)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.error)
                    }
                }
            }

            Button("Remove from Vault", role: .destructive) {
                perform {
                    let ok = await store.removeFromVault(ref)
                    if ok { dismiss() }
                }
            }
            .disabled(inFlight)
        }
    }

    private var foldersSection: some View {
        Section("Folders") {
            if store.folders.isEmpty {
                Text("No folders yet")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                ForEach(store.folders) { folder in
                    Button {
                        perform {
                            let ok: Bool
                            if snap.isVaulted {
                                if snap.folderIDs.contains(folder.id) { return }
                                ok = await store.addToFolder(ref, folderID: folder.id, folderName: folder.name)
                            } else {
                                ok = await store.save(ref, folderID: folder.id, confirmation: "Added to \(folder.name)")
                            }
                            if ok { dismiss() }
                        }
                    } label: {
                        HStack {
                            Text(folder.name)
                            Spacer()
                            if snap.folderIDs.contains(folder.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(colors.accent)
                            }
                        }
                    }
                    .disabled(inFlight || snap.folderIDs.contains(folder.id))
                }
            }

            Button {
                showsNewFolderField.toggle()
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        }
    }

    private var newFolderSection: some View {
        Section {
            TextField("Folder name", text: $newFolderName)
                .textInputAutocapitalization(.words)
            Button("Create and Save") {
                let name = newFolderName
                perform {
                    guard let folder = await store.createFolder(named: name) else { return }
                    newFolderName = ""
                    showsNewFolderField = false
                    let ok: Bool
                    if snap.isVaulted {
                        ok = await store.addToFolder(ref, folderID: folder.id, folderName: folder.name)
                    } else {
                        ok = await store.save(ref, folderID: folder.id, confirmation: "Added to \(folder.name)")
                    }
                    if ok { dismiss() }
                }
            }
            .disabled(
                inFlight
                    || VaultSupport.normalizedFolderName(newFolderName) == nil
            )
        }
    }

    private var membershipFolders: [VaultFolder] {
        store.folders.filter { snap.folderIDs.contains($0.id) }
    }

    private func perform(_ work: @escaping () async -> Void) {
        guard !inFlight else { return }
        inFlight = true
        ExperienceHaptics.play(.selection)
        Task {
            defer { inFlight = false }
            await work()
        }
    }
}
