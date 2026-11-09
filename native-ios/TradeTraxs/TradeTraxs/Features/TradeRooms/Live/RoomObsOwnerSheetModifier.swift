import SwiftUI

/// OBS start-stream sheets — extracted from ``RoomConversationView`` to keep type-check fast.
struct RoomObsOwnerSheetModifier: ViewModifier {
    @Binding var step: ObsOwnerSheetStep?
    let roomID: RoomID
    let roomTitle: String
    @Bindable var controller: TradeRoomObsBroadcastController
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    let chatUserId: String?
    let chatDisplayName: String

    func body(content: Content) -> some View {
        content.sheet(item: $step) { step in
            switch step {
            case .methodSelection:
                TradeRoomStartStreamSheet {
                    self.step = nil
                    broadcastCoordinator.openObsManageStream(roomID: roomID, roomTitle: roomTitle)
                }
            case .manage(let manageRoomID):
                Color.clear
                    .onAppear {
                        self.step = nil
                        broadcastCoordinator.openObsManageStream(roomID: manageRoomID, roomTitle: roomTitle)
                    }
            }
        }
    }
}
