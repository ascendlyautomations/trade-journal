import SwiftUI

/// Native user picker for starting personal or group conversations.
struct NewChatPickerView: View {
    @State private var viewModel: NewChatViewModel
    private let imagePipeline: any ImagePipeline
    var onConversationReady: (Conversation) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        onConversationReady: @escaping (Conversation) -> Void
    ) {
        _viewModel = State(
            initialValue: NewChatViewModel(
                messages: data.messages,
                search: data.search,
                profiles: data.profiles,
                explore: data.explore,
                session: data.session,
                detailCache: data.detailCache
            )
        )
        self.imagePipeline = data.imagePipeline
        self.onConversationReady = onConversationReady
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                newChatTopSection
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .experienceScreenBackground()
            .experienceNavigationTitle(navigationTitle)
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.searchChanged()
            }
            .toolbar { toolbarContent }
            .onDisappear {
                viewModel.dismiss()
            }
            .task {
                await viewModel.prepare()
            }
        }
    }

    private var navigationTitle: String {
        switch viewModel.mode {
        case .chooser: return "New Chat"
        case .personal: return "New Personal Chat"
        case .group: return "New Group Chat"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(viewModel.mode == .chooser ? "Cancel" : "Back") {
                if viewModel.mode == .chooser {
                    viewModel.dismiss()
                    dismiss()
                } else {
                    viewModel.backToChooser()
                }
            }
        }
        if viewModel.mode == .group {
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    Task {
                        if let conversation = await viewModel.createGroup() {
                            onConversationReady(conversation)
                            dismiss()
                        }
                    }
                }
                .disabled(!viewModel.canCreateGroup)
            }
        }
    }

    /// Search + optional create actions — one compact block at the top.
    private var newChatTopSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ExperienceSearchField(
                text: $viewModel.searchText,
                placeholder: "Search people",
                accessibilityIdentifier: "newChat.search"
            )

            if viewModel.mode == .chooser {
                VStack(spacing: ExperienceSpacing.xs) {
                    chooserButton(
                        title: "New Personal Chat",
                        subtitle: "Message one person",
                        icon: .messages
                    ) {
                        viewModel.presentPersonalChat()
                    }
                    chooserButton(
                        title: "New Group Chat",
                        subtitle: "Message several people",
                        icon: .rooms
                    ) {
                        viewModel.presentGroupChat()
                    }
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, ExperienceSpacing.sm)
        .padding(.bottom, ExperienceSpacing.sm)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.mode {
        case .chooser:
            if viewModel.phase == .opening {
                ExperienceLoadingSpinner(label: "Opening conversation")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                ExperienceEmptyState(
                    icon: .warning,
                    title: "Unable to continue",
                    message: error
                )
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                peopleResultsContent(
                    isGroup: false,
                    emptyMessage: "Find a trader to start a conversation."
                )
            }
        case .personal:
            peoplePickerContent(isGroup: false)
        case .group:
            peoplePickerContent(isGroup: true)
        }
    }

    private func chooserButton(
        title: String,
        subtitle: String,
        icon: AppIcon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: ExperienceSpacing.sm) {
                ExperienceIcon(icon: icon, size: .md, color: colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
                Spacer(minLength: 0)
                ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func peoplePickerContent(isGroup: Bool) -> some View {
        if viewModel.phase == .opening {
            ExperienceLoadingSpinner(label: isGroup ? "Creating group" : "Opening conversation")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.phase == .searching, viewModel.isSearching {
            ExperienceLoadingSpinner(label: "Searching people")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            ExperienceEmptyState(
                icon: .warning,
                title: "Unable to continue",
                message: error
            )
            .padding(.horizontal, ExperienceSpacing.md)
        } else {
            VStack(spacing: 0) {
                if isGroup {
                    groupComposerHeader
                }
                peopleResultsContent(
                    isGroup: isGroup,
                    emptyMessage: isGroup
                        ? "Select at least two people, then tap Create."
                        : "Find a trader to start a conversation."
                )
            }
        }
    }

    @ViewBuilder
    private func peopleResultsContent(isGroup: Bool, emptyMessage: String) -> some View {
        if viewModel.phase == .searching, viewModel.isSearching, viewModel.mode == .chooser {
            ExperienceLoadingSpinner(label: "Searching people")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.visibleResults.isEmpty {
            ExperienceEmptyState(
                icon: .search,
                title: viewModel.prompt,
                message: emptyMessage
            )
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            List(viewModel.visibleResults) { profile in
                if isGroup {
                    groupRow(profile)
                } else {
                    personalRow(profile)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var groupComposerHeader: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            TextField("Group name (optional)", text: $viewModel.groupName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, ExperienceSpacing.md)

            if !viewModel.selectedGroupMembers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ExperienceSpacing.xs) {
                        ForEach(viewModel.selectedGroupMembers) { profile in
                            HStack(spacing: 4) {
                                Text(profile.displayName)
                                    .experienceStyle(.caption, color: colors.primaryText)
                                Button {
                                    viewModel.removeGroupMember(profile)
                                } label: {
                                    ExperienceIcon(icon: .close, size: .xs, color: colors.secondaryText)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(colors.backgroundSecondary)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                }
            }
        }
        .padding(.bottom, ExperienceSpacing.xs)
    }

    private func personalRow(_ profile: Profile) -> some View {
        Button {
            Task {
                if let conversation = await viewModel.select(profile) {
                    onConversationReady(conversation)
                    dismiss()
                }
            }
        } label: {
            profileRow(profile, showsSelection: false, isSelected: false)
        }
        .buttonStyle(.plain)
        .listRowBackground(colors.backgroundPrimary)
    }

    private func groupRow(_ profile: Profile) -> some View {
        Button {
            viewModel.toggleGroupMember(profile)
        } label: {
            profileRow(
                profile,
                showsSelection: true,
                isSelected: viewModel.isGroupMemberSelected(profile)
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(colors.backgroundPrimary)
    }

    private func profileRow(_ profile: Profile, showsSelection: Bool, isSelected: Bool) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            FollowListAvatarView(profile: profile, imagePipeline: imagePipeline)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .experienceStyle(.body, color: colors.primaryText)
                Text("@\(profile.username)")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Spacer()
            if showsSelection {
                if isSelected {
                    ExperienceIcon(icon: .success, size: .md, color: colors.accent)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: IconSizeToken.md.value))
                        .foregroundStyle(colors.tertiaryText)
                }
            } else {
                ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
            }
        }
        .contentShape(Rectangle())
    }
}
