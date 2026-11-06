import SwiftUI

extension View {
    func tradeRoomBroadcastViewerSheet(
        coordinator: RoomBroadcastCoordinator,
        currentUserProfile: CurrentUserProfileStore,
        imagePipeline: any ImagePipeline
    ) -> some View {
        sheet(isPresented: Binding(
            get: { coordinator.isViewerPresented },
            set: { presented in
                if presented {
                    coordinator.presentViewer()
                } else {
                    coordinator.minimizeViewer()
                }
            }
        )) {
            if let session = coordinator.watchSession {
                RoomBroadcastWatchView(
                    roomID: session.roomID,
                    roomTitle: session.roomTitle,
                    userId: currentUserProfile.profile?.id.rawValue,
                    displayName: currentUserProfile.profile?.displayName ?? "You",
                    imagePipeline: imagePipeline,
                    coordinator: coordinator
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(false)
            }
        }
    }
}
