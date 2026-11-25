import SwiftUI

/// Fallback when the manage sheet loses its room anchor (should be rare after ``obsManageStreamPresentation``).
private struct TradeRoomObsManageStreamRecoveryView: View {
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    @Bindable var obsController: TradeRoomObsBroadcastController
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                Text("OBS setup didn’t load correctly.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                if let err = obsController.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(colors.error)
                }
                Button("Try again") {
                    if let roomID = obsController.hostContextRoomID {
                        broadcastCoordinator.openObsManageStream(
                            roomID: roomID,
                            roomTitle: obsController.hostContextRoomTitle ?? "Trade Room"
                        )
                        obsController.retryPrivateObsSessionEnsure(roomID: roomID)
                    } else {
                        broadcastCoordinator.setObsManageStreamPresented(false)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(ExperienceSpacing.md)
            .background(colors.primaryBackground)
            .navigationTitle("OBS stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        broadcastCoordinator.setObsManageStreamPresented(false)
                    }
                }
            }
        }
        .onAppear {
            if let roomID = obsController.hostContextRoomID {
                TradeRoomObsBroadcastDiagnostics.log(
                    "sheet.recovery",
                    roomID: roomID,
                    detail: "missingPresentationAnchor"
                )
            }
        }
    }
}

extension View {
    func tradeRoomObsManageStreamSheet(
        broadcastCoordinator: RoomBroadcastCoordinator,
        obsController: TradeRoomObsBroadcastController,
        currentUserProfile: CurrentUserProfileStore,
        imagePipeline: any ImagePipeline
    ) -> some View {
        sheet(
            isPresented: Binding(
                get: { broadcastCoordinator.isObsManageStreamPresented },
                set: { presented in
                    broadcastCoordinator.setObsManageStreamPresented(presented)
                }
            ),
            onDismiss: {
                if obsController.phase == .livePublic || obsController.phase == .preparing {
                    obsController.acknowledgeManagementSheetDismissed()
                }
            }
        ) {
            if let session =
                broadcastCoordinator.obsManageStreamPresentation
                ?? broadcastCoordinator.obsHostBarSession
            {
                TradeRoomObsBroadcastManagementSheet(
                    roomID: session.roomID,
                    roomTitle: session.roomTitle,
                    controller: obsController,
                    broadcastCoordinator: broadcastCoordinator,
                    imagePipeline: imagePipeline,
                    chatUserId: currentUserProfile.profile?.id.rawValue,
                    chatDisplayName: currentUserProfile.profile?.displayName ?? "You"
                )
            } else {
                TradeRoomObsManageStreamRecoveryView(
                    broadcastCoordinator: broadcastCoordinator,
                    obsController: obsController
                )
            }
        }
    }
}
