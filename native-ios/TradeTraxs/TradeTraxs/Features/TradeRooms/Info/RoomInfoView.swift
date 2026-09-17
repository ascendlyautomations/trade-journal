import SwiftUI
import UIKit

struct RoomInfoView: View {
    @State private var viewModel: RoomInfoViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var logoImage: Image?
    @State private var ownerAvatarImage: Image?
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
        .task(id: viewModel.ownerProfile?.id) {
            await loadOwnerAvatar()
        }
        .confirmationDialog(
            "Leave this Trade Room?",
            isPresented: $viewModel.showsLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave Room", role: .destructive) {
                Task { await viewModel.leaveRoom() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can rejoin later if the room is still available.")
        }
        .accessibilityIdentifier("tradeRooms.info")
    }

    private var content: some View {
        List {
            Section {
                roomHeader
            }
            .listRowInsets(EdgeInsets(
                top: ExperienceSpacing.sm,
                leading: ExperienceSpacing.md,
                bottom: ExperienceSpacing.sm,
                trailing: ExperienceSpacing.md
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                membersRow
                inviteLinkRow
                ownerRow
            }

            if viewModel.canManageRoom {
                Section {
                    Button("Trade Room Settings") {
                        viewModel.openRoomSettings()
                    }
                }
            } else if viewModel.isMember {
                Section {
                    Button("Leave Room", role: .destructive) {
                        viewModel.showsLeaveConfirmation = true
                    }
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
        .listSectionSpacing(ExperienceSpacing.sm)
        .scrollContentBackground(.hidden)
    }

    private var roomHeader: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.md) {
            roomLogo(size: 72)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(viewModel.room?.name ?? "Trade Room")
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Text(roomMetadataLine)
                    .experienceStyle(.footnote, color: colors.secondaryText)

                Text(displayDescription)
                    .experienceStyle(.footnote, color: colors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var roomMetadataLine: String {
        let visibility = viewModel.room?.isPrivate == true ? "Private" : "Public"
        let count = ProfileDisplay.compactCount(viewModel.displayedMemberCount ?? 0)
        let memberLabel = (viewModel.displayedMemberCount ?? 0) == 1 ? "member" : "members"
        return "\(visibility) · \(count) \(memberLabel)"
    }

    private var displayDescription: String {
        guard let raw = viewModel.room?.description else { return "No description" }
        let description = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty || description.caseInsensitiveCompare("Personal Trade Room") == .orderedSame {
            return "No description"
        }
        return description
    }

    private var membersRow: some View {
        Button {
            viewModel.openMembers()
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                Text("Members")
                    .experienceStyle(.body, color: colors.primaryText)
                Spacer(minLength: ExperienceSpacing.xs)
                Text(ProfileDisplay.compactCount(viewModel.displayedMemberCount ?? 0))
                    .experienceStyle(.body, color: colors.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
        }
        .accessibilityIdentifier("tradeRooms.info.members")
    }

    private var inviteLinkRow: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Invite Link")
                    .experienceStyle(.body, color: colors.primaryText)
                Text("Share room invite")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
            Spacer(minLength: ExperienceSpacing.xs)
            Button(inviteLinkCopied ? "Copied" : "Copy") {
                copyInviteLink()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.accent)
            .accessibilityIdentifier("tradeRooms.info.invite.copy")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var ownerRow: some View {
        if let owner = viewModel.ownerProfile {
            Button {
                viewModel.openOwner()
            } label: {
                HStack(spacing: ExperienceSpacing.sm) {
                    ExperienceAvatar(
                        initials: ProfileDisplay.initials(
                            displayName: owner.displayName,
                            username: owner.username
                        ),
                        image: ownerAvatarImage,
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Owner")
                            .experienceStyle(.caption, color: colors.tertiaryText)
                        Text(owner.displayName)
                            .experienceStyle(.body, color: colors.primaryText)
                            .lineLimit(1)
                        Text("@\(owner.username)")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: ExperienceSpacing.xs)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
            }
            .accessibilityIdentifier("tradeRooms.info.owner")
        } else {
            HStack {
                Text("Owner")
                    .experienceStyle(.body, color: colors.primaryText)
                Spacer()
                Text("Unavailable")
                    .experienceStyle(.footnote, color: colors.tertiaryText)
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

    private func roomLogo(size: CGFloat) -> some View {
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
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
        .accessibilityHidden(true)
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
                    maxPixelSize: 192
                )
            )
            if let ui = UIImage(data: data) {
                logoImage = Image(uiImage: ui)
            }
        } catch {
            logoImage = nil
        }
    }

    private func loadOwnerAvatar() async {
        guard let reference = viewModel.ownerProfile?.avatar else {
            ownerAvatarImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 96
                )
            )
            if let ui = UIImage(data: data) {
                ownerAvatarImage = Image(uiImage: ui)
            }
        } catch {
            ownerAvatarImage = nil
        }
    }
}
