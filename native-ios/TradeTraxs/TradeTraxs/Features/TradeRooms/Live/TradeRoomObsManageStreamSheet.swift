import SwiftUI

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
                if obsController.phase == .livePublic {
                    obsController.acknowledgeManagementSheetDismissed()
                }
            }
        ) {
            if let session = broadcastCoordinator.obsHostBarSession {
                TradeRoomObsBroadcastManagementSheet(
                    roomID: session.roomID,
                    roomTitle: session.roomTitle,
                    controller: obsController,
                    broadcastCoordinator: broadcastCoordinator,
                    imagePipeline: imagePipeline,
                    chatUserId: currentUserProfile.profile?.id.rawValue,
                    chatDisplayName: currentUserProfile.profile?.displayName ?? "You"
                )
            }
        }
    }
}
