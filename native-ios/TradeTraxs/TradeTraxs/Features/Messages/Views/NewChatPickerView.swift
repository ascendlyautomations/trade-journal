import SwiftUI

/// Native user picker for starting a DM — reuses FollowList avatar + image pipeline.
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
                session: data.session,
                detailCache: data.detailCache
            )
        )
        self.imagePipeline = data.imagePipeline
        self.onConversationReady = onConversationReady
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.phase == .opening {
                    ExperienceLoadingSpinner(label: "Opening conversation")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.visibleResults.isEmpty {
                    ExperienceEmptyState(
                        icon: .search,
                        title: viewModel.prompt,
                        message: "Find a trader to start a conversation."
                    )
                } else {
                    List(viewModel.visibleResults) { profile in
                        Button {
                            Task {
                                if let conversation = await viewModel.select(profile) {
                                    onConversationReady(conversation)
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: ExperienceSpacing.sm) {
                                FollowListAvatarView(profile: profile, imagePipeline: imagePipeline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                        .experienceStyle(.body, color: colors.primaryText)
                                    Text("@\(profile.username)")
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                                Spacer()
                                ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(colors.backgroundPrimary)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .experienceScreenBackground()
            .experienceNavigationTitle("New Chat")
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search people"
            )
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.searchChanged()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await viewModel.prepare()
            }
        }
    }
}
