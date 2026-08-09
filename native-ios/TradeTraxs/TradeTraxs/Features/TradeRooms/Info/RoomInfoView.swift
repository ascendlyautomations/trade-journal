import SwiftUI
import UIKit

struct RoomInfoView: View {
    @State private var viewModel: RoomInfoViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var logoImage: Image?

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
        .navigationTitle("Room Info")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.loadIfNeeded()
        }
        .task(id: viewModel.room?.image?.id) {
            await loadLogo()
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
        }
        .confirmationDialog(
            "Report this Trade Room?",
            isPresented: $viewModel.showsReportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Report Room", role: .destructive) {
                viewModel.reportRoom()
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("tradeRooms.info")
    }

    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    banner
                    HStack(spacing: ExperienceSpacing.sm) {
                        logo
                        VStack(alignment: .leading, spacing: 3) {
                            Text(viewModel.room?.name ?? "Trade Room")
                                .experienceStyle(.headline, color: colors.primaryText)
                            Text("\(ProfileDisplay.compactCount(viewModel.room?.memberCount ?? 0)) members")
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

            if !viewModel.moderators.isEmpty {
                Section("Moderators") {
                    ForEach(viewModel.moderators) { mod in
                        Text(mod.displayName)
                            .experienceStyle(.body, color: colors.primaryText)
                    }
                }
            }

            Section {
                Button("Members") {
                    viewModel.openMembers()
                }
                Button("Leave Room", role: .destructive) {
                    viewModel.showsLeaveConfirmation = true
                }
                Button("Report Room", role: .destructive) {
                    viewModel.showsReportConfirmation = true
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

    private var banner: some View {
        LinearGradient(
            colors: [colors.accent.opacity(0.4), colors.fillSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
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
