import SwiftUI

/// OBS start-stream sheets — extracted from ``RoomConversationView`` to keep type-check fast.
struct RoomObsOwnerSheetModifier: ViewModifier {
    @Binding var step: ObsOwnerSheetStep?
    let roomID: RoomID
    let roomTitle: String
    @Bindable var controller: TradeRoomObsBroadcastController

    func body(content: Content) -> some View {
        content.sheet(item: $step) { step in
            switch step {
            case .methodSelection:
                TradeRoomStartStreamSheet {
                    self.step = .manage(roomID: roomID)
                }
            case .manage(let manageRoomID):
                TradeRoomObsBroadcastManagementSheet(
                    roomID: manageRoomID,
                    roomTitle: roomTitle,
                    controller: controller
                )
            }
        }
    }
}
