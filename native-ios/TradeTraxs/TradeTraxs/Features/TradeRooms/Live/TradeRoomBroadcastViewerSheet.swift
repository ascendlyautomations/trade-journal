import SwiftUI

extension View {
    func tradeRoomBroadcastViewerSheet(
        coordinator: RoomBroadcastCoordinator,
        currentUserProfile: CurrentUserProfileStore,
        imagePipeline: any ImagePipeline
    ) -> some View {
        sheet(isPresented: Binding(
            get: {
                coordinator.viewerPresentation == .expanded
                    && !coordinator.suppressesBroadcastViewerSheet
            },
            set: { presented in
                if presented {
                    coordinator.presentExpandedLivestreamChrome()
                } else if coordinator.viewerPresentation == .expanded {
                    coordinator.minimizeViewer()
                }
            }
        )) {
            if let denial = coordinator.viewerSessionAccessDenied {
                BroadcastViewerSessionAccessDeniedView(
                    denial: denial,
                    coordinator: coordinator
                )
                .experienceSheetChrome(
                    detents: [.large],
                    dragIndicator: .hidden,
                    interactiveDismiss: false,
                    keyboardDoneToolbar: false
                )
            } else if let session = coordinator.watchSession {
                RoomBroadcastWatchView(
                    roomID: session.roomID,
                    roomTitle: session.roomTitle,
                    userId: currentUserProfile.profile?.id.rawValue,
                    displayName: currentUserProfile.profile?.displayName ?? "You",
                    imagePipeline: imagePipeline,
                    coordinator: coordinator
                )
                .experienceSheetChrome(
                    detents: [.large],
                    dragIndicator: .hidden,
                    interactiveDismiss: false,
                    keyboardDoneToolbar: false
                )
            }
        }
    }
}
