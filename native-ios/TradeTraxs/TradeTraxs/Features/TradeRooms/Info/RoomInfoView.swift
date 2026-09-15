import SwiftUI
import UIKit

struct RoomInfoView: View {
    @State private var viewModel: RoomInfoViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var logoImage: Image?
    @State private var inviteLinkCopied = false

    init(
        roomID: RoomID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages
    ) {
        _viewModel = State(
            initialValue: RoomInfoViewModel(
                roomID: roomID,
                rooms: data.rooms,
                uploadService: data.uploadService,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                navigationHost: navigationHost
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    init(viewModel: RoomInfoViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ExperienceLoadingSpinner(label: "Loading room info")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't load room info",
                    message: message,
                    onRetry: { viewModel.retry() }
                )
            case .loaded:
                content
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Room Info")
        .task {
            viewModel.loadIfNeeded()
        }
        .task(id: viewModel.room?.image?.id) {
            await loadLogo()
        }
        .accessibilityIdentifier("tradeRooms.info")
    }

    private var content: some View {
        List {
            roomNameSection
            roomPictureSection
            membersSection
            descriptionSection
            inviteLinkSection

            Section("Owner") {
                if let owner = viewModel.ownerProfile {
                    Button {
                        viewModel.openOwner()
                    } label: {
                        HStack {
                            Text(owner.displayName)
                                .experienceStyle(.body, color: colors.primaryText)
                            Spacer()
                            Text("@\(owner.username)")
                                .experienceStyle(.caption, color: colors.secondaryText)
                        }
                    }
                } else {
                    Text("Unavailable")
                        .experienceStyle(.body, color: colors.tertiaryText)
                }
            }

            Section {
                Button("Trade Room Settings") {
                    viewModel.openRoomSettings()
                }
            }

            if !viewModel.isOwner {
                Section {
                    Button("Report Room") {
                        ExperienceHaptics.play(.selection)
                        ContentReportSupport.presentTradeRoom(
                            roomID: viewModel.roomID,
                            roomName: viewModel.room?.name,
                            ownerID: viewModel.room?.ownerProfileID,
                            presenter: appEnvironment.contentReportPresenter
                        )
                    }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section {
                    Text(statusMessage)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var roomNameSection: some View {
        Section("Room Name") {
            Text(viewModel.room?.name ?? "Trade Room")
                .experienceStyle(.body, color: colors.primaryText)
        }
    }

    private var roomPictureSection: some View {
        Section("Room Picture") {
            HStack(spacing: ExperienceSpacing.md) {
                logo
                Spacer(minLength: 0)
            }
        }
    }

    private var membersSection: some View {
        Section("Members") {
            Button {
                viewModel.openMembers()
            } label: {
                HStack {
                    Text("\(ProfileDisplay.compactCount(viewModel.displayedMemberCount ?? 0)) members")
                        .experienceStyle(.body, color: colors.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        Section("Description") {
            if let raw = viewModel.room?.description {
                let description = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if description.isEmpty
                    || description.caseInsensitiveCompare("Personal Trade Room") == .orderedSame
                {
                    Text("No description")
                        .experienceStyle(.body, color: colors.tertiaryText)
                } else {
                    Text(description)
                        .experienceStyle(.body, color: colors.primaryText)
                }
            } else {
                Text("No description")
                    .experienceStyle(.body, color: colors.tertiaryText)
            }
        }
    }

    private var inviteLinkSection: some View {
        Section("Invite Link") {
            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                Text(viewModel.inviteLink)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(inviteLinkCopied ? "Copied" : "Copy") {
                    copyInviteLink()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.accent)
                .accessibilityIdentifier("tradeRooms.info.invite.copy")
            }
        }
    }

    private func copyInviteLink() {
        UIPasteboard.general.string = viewModel.inviteLink
        ExperienceHaptics.play(.selection)
        inviteLinkCopied = true
        viewModel.statusMessage = "Invite link copied."
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            inviteLinkCopied = false
        }
    }

    private var logo: some View {
        Group {
            if let logoImage {
                logoImage.resizable().scaledToFill()
            } else {
                ZStack {
                    colors.fillSecondary
                    ExperienceIcon(icon: .rooms, size: .md, color: colors.accent)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }

    private func loadLogo() async {
        guard let reference = viewModel.room?.image else {
            logoImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 160
                )
            )
            if let ui = UIImage(data: data) {
                logoImage = Image(uiImage: ui)
            }
        } catch {
            logoImage = nil
        }
    }
}
