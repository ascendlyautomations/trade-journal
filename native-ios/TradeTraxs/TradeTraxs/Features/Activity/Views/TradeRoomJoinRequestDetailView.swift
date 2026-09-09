import SwiftUI

struct TradeRoomJoinRequestDetailView: View {
    @State private var viewModel: TradeRoomJoinRequestDetailViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    init(
        requestID: String,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages
    ) {
        _viewModel = State(
            initialValue: TradeRoomJoinRequestDetailViewModel(
                requestID: requestID,
                rooms: data.rooms,
                profiles: data.profiles,
                supabase: data.supabase,
                navigationCoordinator: navigationCoordinator,
                navigationHost: navigationHost
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ExperienceLoadingSpinner(label: "Loading join request")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't load join request",
                    message: message,
                    onRetry: { viewModel.retry() }
                )
            case .loaded:
                content
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Join Request")
        .task { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("activity.tradeRoomJoinRequest.detail")
    }

    @ViewBuilder
    private var content: some View {
        List {
            if let requester = viewModel.requester {
                Section {
                    Button {
                        viewModel.openRequester()
                    } label: {
                        HStack(spacing: ExperienceSpacing.sm) {
                            FollowListAvatarView(
                                profile: requester,
                                imagePipeline: imagePipeline,
                                size: 48
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(requester.username)")
                                    .experienceStyle(.headline, color: colors.primaryText)
                                if !requester.displayName.isEmpty, requester.displayName != requester.username {
                                    Text(requester.displayName)
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                            }
                            Spacer()
                            ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Requester")
                }
            }

            if let room = viewModel.room {
                Section {
                    Button {
                        viewModel.openRoom()
                    } label: {
                        HStack(spacing: ExperienceSpacing.sm) {
                            RoomJoinRequestAvatarView(
                                room: room,
                                imagePipeline: imagePipeline,
                                size: 48
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(room.name)
                                    .experienceStyle(.headline, color: colors.primaryText)
                                if room.roomKind == .official {
                                    Text("Official Trade Room")
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                            }
                            Spacer()
                            ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Trade Room")
                }
            }

            if viewModel.canResolve {
                Section {
                    Button {
                        Task { await viewModel.approve() }
                    } label: {
                        Text("Accept")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(viewModel.isMutating)
                    .accessibilityIdentifier("activity.tradeRoomJoinRequest.accept")

                    Button(role: .destructive) {
                        Task { await viewModel.decline() }
                    } label: {
                        Text("Decline")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(viewModel.isMutating)
                    .accessibilityIdentifier("activity.tradeRoomJoinRequest.decline")
                }
            } else if let label = viewModel.resolvedStatusLabel {
                Section {
                    Text(label)
                        .experienceStyle(.body, color: colors.secondaryText)
                } header: {
                    Text("Status")
                } footer: {
                    Text("This join request is no longer pending.")
                }
            } else {
                Section {
                    Text("Request no longer available")
                        .experienceStyle(.body, color: colors.secondaryText)
                }
            }

            if let message = viewModel.statusMessage {
                Section {
                    Text(message)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

private struct RoomJoinRequestAvatarView: View {
    let room: TradeRoom
    let imagePipeline: any ImagePipeline
    var size: CGFloat = 48

    @State private var image: Image?

    var body: some View {
        ExperienceAvatar(
            initials: ProfileDisplay.initials(displayName: room.name, username: room.slug),
            image: image,
            size: size
        )
        .task(id: room.image?.id) {
            await load()
        }
    }

    private func load() async {
        guard let reference = room.image else {
            image = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 128
                )
            )
            if let ui = UIImage(data: data) {
                image = Image(uiImage: ui)
            }
        } catch {
            image = nil
        }
    }
}
