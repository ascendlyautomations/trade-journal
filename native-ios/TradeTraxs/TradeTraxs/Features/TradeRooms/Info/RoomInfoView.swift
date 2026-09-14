import SwiftUI
import UIKit
import PhotosUI

struct RoomInfoView: View {
    @State private var viewModel: RoomInfoViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var logoImage: Image?
    @State private var photoItem: PhotosPickerItem?
    @State private var cropSourceImage: UIImage?

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
        .experienceNavigationTitle(viewModel.canManageRoom ? "Room Information" : "Room Info")
        .toolbar {
            if viewModel.canManageRoom, case .loaded = viewModel.phase {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await viewModel.saveDetails() }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isSavingDetails)
                    .accessibilityIdentifier("tradeRooms.info.save")
                }
            }
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .task(id: viewModel.room?.image?.id) {
            await loadLogo()
        }
        .onChange(of: photoItem) { _, item in
            Task { await presentRoomImageCrop(for: item) }
        }
        .imageCropSelection(
            sourceImage: $cropSourceImage,
            preset: .room,
            onConfirm: { result in
                viewModel.setCroppedRoomImage(result)
                cropSourceImage = nil
                photoItem = nil
            },
            onCancel: {
                photoItem = nil
            }
        )
        .confirmationDialog(
            "Leave this Trade Room?",
            isPresented: $viewModel.showsLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave Room", role: .destructive) {
                Task { await viewModel.leaveRoom() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("tradeRooms.info")
    }

    private var content: some View {
        List {
            if viewModel.canManageRoom {
                ownerEditorSections
            } else {
                readOnlyHeaderSection
            }
            sharedFooterSections
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .experienceProtectedFormDismiss(viewModel.canManageRoom && viewModel.isSavingDetails)
        .disabled(viewModel.isSavingDetails)
    }

    @ViewBuilder
    private var ownerEditorSections: some View {
        Section {
            HStack(spacing: ExperienceSpacing.sm) {
                logo
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Room name", text: $viewModel.editName)
                        .font(.headline)
                    Text("\(ProfileDisplay.compactCount(viewModel.displayedMemberCount ?? 0)) members")
                        .experienceStyle(.caption, color: colors.secondaryText)
                    if viewModel.pendingImagePreview != nil {
                        Text("New photo selected")
                            .experienceStyle(.caption2, color: colors.accent)
                    }
                }
            }
            .listRowBackground(colors.backgroundSecondary)
        }

        Section("Description") {
            TextField("Description", text: $viewModel.editDescription, axis: .vertical)
                .lineLimit(3...6)
        }

        Section("Picture") {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose New Picture", systemImage: "photo")
            }
        }

        Section("Privacy") {
            Toggle("Show on my profile", isOn: $viewModel.editShowsOnProfile)
        }

        Section("Manage") {
            Button("Manage Room") { viewModel.openManageRoom() }
            Button("Members") { viewModel.openMembers() }
        }
    }

    @ViewBuilder
    private var readOnlyHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                HStack(spacing: ExperienceSpacing.sm) {
                    logo
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.room?.name ?? "Trade Room")
                            .experienceStyle(.headline, color: colors.primaryText)
                        Text("\(ProfileDisplay.compactCount(viewModel.displayedMemberCount ?? 0)) members")
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                }
                if let raw = viewModel.room?.description {
                    let description = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !description.isEmpty,
                       description.caseInsensitiveCompare("Personal Trade Room") != .orderedSame
                    {
                        Text(description)
                            .experienceStyle(.body, color: colors.primaryText)
                    }
                }
            }
            .listRowBackground(colors.backgroundSecondary)
        }
    }

    @ViewBuilder
    private var sharedFooterSections: some View {
        Section("Rules") {
            Text(viewModel.rulesText)
                .experienceStyle(.footnote, color: colors.secondaryText)
        }

        Section("Invite") {
            Button {
                UIPasteboard.general.string = viewModel.inviteLink
                ExperienceHaptics.play(.selection)
                viewModel.statusMessage = "Invite link copied."
            } label: {
                HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                    Image(systemName: "link")
                    Text(viewModel.inviteLink)
                        .experienceStyle(.footnote, color: colors.accent)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }

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

        if !viewModel.isOwner {
            Section {
                Button("Members") {
                    viewModel.openMembers()
                }
                Button("Leave Room", role: .destructive) {
                    viewModel.showsLeaveConfirmation = true
                }
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
        } else {
            Section {
                Button("Leave Room", role: .destructive) {
                    viewModel.showsLeaveConfirmation = true
                }
            }
        }

        if let statusMessage = viewModel.statusMessage {
            Section {
                Text(statusMessage)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }

        if viewModel.isSavingDetails {
            Section {
                HStack {
                    ProgressView()
                    Text("Saving…")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
        }
    }

    private var logo: some View {
        Group {
            if let pending = viewModel.pendingImagePreview {
                Image(uiImage: pending)
                    .resizable()
                    .scaledToFill()
            } else if let logoImage {
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

    private func presentRoomImageCrop(for item: PhotosPickerItem?) async {
        guard let image = await ImageCropSelectionSupport.loadUIImage(from: item) else { return }
        cropSourceImage = image
    }

    private func loadLogo() async {
        if viewModel.pendingImagePreview != nil {
            return
        }
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
