import SwiftUI

struct RoomSettingsView: View {
    @State private var viewModel: RoomSettingsViewModel

    @Environment(\.themeColors) private var colors

    init(
        roomID: RoomID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages
    ) {
        _viewModel = State(
            initialValue: RoomSettingsViewModel(
                roomID: roomID,
                rooms: data.rooms,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                navigationHost: navigationHost
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ExperienceLoadingSpinner(label: "Loading settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't load settings",
                    message: message,
                    onRetry: { viewModel.retry() }
                )
            case .loaded:
                settingsContent
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Trade Room Settings")
        .task { viewModel.loadIfNeeded() }
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
            "Delete Trade Room?",
            isPresented: $viewModel.showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Room", role: .destructive) {
                Task { await viewModel.deleteRoom() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Deleting this room will permanently remove the room and its associated room content and membership according to the existing backend deletion semantics."
            )
        }
        .accessibilityIdentifier("tradeRooms.settings")
    }

    private var settingsContent: some View {
        List {
            if !viewModel.isOwner {
                Section {
                    Button("Leave Room", role: .destructive) {
                        viewModel.showsLeaveConfirmation = true
                    }
                    .disabled(viewModel.isLeaving)
                }
            }

            if viewModel.canDeleteRoom {
                Section {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        Text("Danger Zone")
                            .experienceStyle(.caption, color: colors.loss)
                            .textCase(.uppercase)
                        Button("Delete Trade Room", role: .destructive) {
                            viewModel.showsDeleteConfirmation = true
                        }
                        .disabled(viewModel.isDeleting)
                    }
                    .padding(.vertical, ExperienceSpacing.xxs)
                }
            }

            if viewModel.isLeaving || viewModel.isDeleting {
                Section {
                    HStack {
                        ProgressView()
                        Text(viewModel.isDeleting ? "Deleting…" : "Leaving…")
                            .experienceStyle(.footnote, color: colors.secondaryText)
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
}
