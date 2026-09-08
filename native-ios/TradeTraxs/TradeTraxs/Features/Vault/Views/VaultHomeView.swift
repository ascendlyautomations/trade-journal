import SwiftUI

struct VaultHomeView: View {
    @State private var viewModel: VaultHomeViewModel
    @Bindable private var vaultStore: VaultStore
    @State private var newFolderName = ""
    @State private var showsNewFolderAlert = false
    @State private var folderPendingDelete: VaultFolder?
    @State private var folderPendingRename: VaultFolder?
    @State private var renameFolderName = ""
    @State private var folderRenameError: String?
    @Environment(\.themeColors) private var colors

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: VaultHomeViewModel(
                repository: data.vault,
                navigationCoordinator: navigationCoordinator
            )
        )
        _vaultStore = Bindable(wrappedValue: data.vaultStore)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                filterBar
                foldersSection
                itemsSection
            }
            .experiencePadding(.horizontal, .md)
            .padding(.vertical, ExperienceSpacing.md)
        }
        .experienceScreenBackground()
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.refresh(store: vaultStore)
        }
        .onAppear {
            viewModel.onAppear(store: vaultStore)
        }
        .onChange(of: viewModel.filter) { _, _ in
            Task { await viewModel.refresh(store: vaultStore) }
        }
        .onChange(of: viewModel.selectedFolderID) { _, _ in
            Task { await viewModel.refresh(store: vaultStore) }
        }
        .alert("New Folder", isPresented: $showsNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName
                newFolderName = ""
                Task { await viewModel.createFolder(named: name, store: vaultStore) }
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { folderPendingRename != nil },
            set: { if !$0 { folderPendingRename = nil; folderRenameError = nil } }
        )) {
            TextField("Folder name", text: $renameFolderName)
            Button("Save") {
                guard let folder = folderPendingRename else { return }
                let name = renameFolderName
                Task {
                    if let error = await viewModel.renameFolder(folder, to: name, store: vaultStore) {
                        folderRenameError = error
                    } else {
                        folderPendingRename = nil
                        renameFolderName = ""
                        folderRenameError = nil
                    }
                }
            }
            .disabled(VaultSupport.normalizedFolderName(renameFolderName) == nil)
            Button("Cancel", role: .cancel) {
                folderPendingRename = nil
                renameFolderName = ""
                folderRenameError = nil
            }
        } message: {
            if let folderRenameError {
                Text(folderRenameError)
            }
        }
        .confirmationDialog(
            "Delete Folder?",
            isPresented: Binding(
                get: { folderPendingDelete != nil },
                set: { if !$0 { folderPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let folder = folderPendingDelete {
                Button("Delete \"\(folder.name)\"", role: .destructive) {
                    Task { await viewModel.deleteFolder(folder, store: vaultStore) }
                    folderPendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                folderPendingDelete = nil
            }
        } message: {
            Text("Removes the folder only. Saved items stay in your Vault.")
        }
        .accessibilityIdentifier("vault.home")
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.sm) {
                ForEach(VaultContentFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: VaultContentFilter) -> some View {
        let selected = viewModel.filter == filter && viewModel.selectedFolderID == nil
        return Button {
            viewModel.selectFilter(filter)
        } label: {
            Text(filterLabel(filter))
                .experienceStyle(.caption, color: selected ? colors.textInverse : colors.primaryText)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs)
                .background {
                    Capsule(style: .continuous)
                        .fill(selected ? colors.accent : colors.fillPrimary)
                }
        }
        .buttonStyle(.plain)
    }

    private func filterLabel(_ filter: VaultContentFilter) -> String {
        switch filter {
        case .all: return "All"
        case .trades: return "Trades"
        case .clips: return "Clips"
        case .posts: return "Posts"
        case .achievements: return "Achievements"
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Folders")
                .experienceStyle(.headline, color: colors.primaryText)

            if viewModel.folders.isEmpty {
                Text("Create folders to organize saved content.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                ForEach(viewModel.folders) { folder in
                    Button {
                        viewModel.selectFolder(
                            viewModel.selectedFolderID == folder.id ? nil : folder
                        )
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(
                                    viewModel.selectedFolderID == folder.id
                                        ? colors.accent
                                        : colors.secondaryText
                                )
                            Text(folder.name)
                                .experienceStyle(.body, color: colors.primaryText)
                            Spacer()
                        }
                        .padding(.vertical, ExperienceSpacing.xs)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename") {
                            folderPendingRename = folder
                            renameFolderName = folder.name
                            folderRenameError = nil
                        }
                        Button("Delete Folder", role: .destructive) {
                            folderPendingDelete = folder
                        }
                    }
                }
            }

            Button {
                showsNewFolderAlert = true
            } label: {
                HStack(spacing: ExperienceSpacing.xs) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(colors.accent)
                    Text("New Folder")
                        .experienceStyle(.body, color: colors.accent)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var itemsSection: some View {
        Text(viewModel.selectedFolderID == nil ? "Recent" : "In Folder")
            .experienceStyle(.headline, color: colors.primaryText)

        switch viewModel.phase {
        case .idle where viewModel.items.isEmpty, .loading where viewModel.items.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, ExperienceSpacing.lg)
        case .failed(let message):
            ExperienceEmptyState(
                icon: .warning,
                title: "Couldn’t load Vault",
                message: message
            )
        case .idle, .loaded, .loading:
            if viewModel.items.isEmpty {
                ExperienceEmptyState(
                    icon: .empty,
                    title: "Nothing saved yet",
                    message: "Tap the hexagon on posts, trades, clips, and achievements to add them here."
                )
            } else {
                LazyVStack(spacing: ExperienceSpacing.sm) {
                    ForEach(viewModel.items) { item in
                        VaultItemRow(item: item) {
                            viewModel.open(item)
                        }
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(currentID: item.id) }
                        }
                    }
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .padding(.vertical, ExperienceSpacing.sm)
                    }
                }
            }
        }
    }
}

private struct VaultItemRow: View {
    let item: VaultItem
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: ExperienceSpacing.sm) {
                Image(systemName: "hexagon.fill")
                    .foregroundStyle(colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .experienceStyle(.body, color: colors.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(ExperienceSpacing.sm)
            .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        switch item.ref.contentType {
        case .trade: return "Trade"
        case .profilePost, .feedPost: return "Post"
        case .reel: return "Clip"
        case .achievement: return "Achievement"
        }
    }

    private var subtitle: String {
        let date = MessagesInboxSupport.relativeTimestamp(item.createdAt)
        return "\(item.ref.contentType.filterLabel) · \(date)"
    }
}
