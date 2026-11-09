import SwiftUI

/// Live-broadcast side effects extracted from ``RoomConversationView`` for faster type-checking.
struct RoomConversationBroadcastLifecycleModifier: ViewModifier {
    var viewModel: RoomConversationViewModel
    var tryOpenLiveBroadcast: () async -> Void
    var handleWillEnterForeground: () -> Void
    var reloadRoomMetadata: () async -> Void
    var reloadChannels: () async -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.phase) { _, phase in
                guard phase == .loaded, viewModel.room != nil else { return }
                Task { await tryOpenLiveBroadcast() }
            }
            .onChange(of: viewModel.pendingOpenLiveBroadcast) { _, pending in
                guard pending else { return }
                Task { await tryOpenLiveBroadcast() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                handleWillEnterForeground()
            }
            .onReceive(NotificationCenter.default.publisher(for: .tradeRoomMetadataDidChange)) { notification in
                guard let changedID = notification.object as? RoomID,
                      changedID == viewModel.roomID
                else { return }
                Task { await reloadRoomMetadata() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tradeRoomChannelsDidChange)) { notification in
                guard let changedID = notification.object as? RoomID,
                      changedID == viewModel.roomID
                else { return }
                Task { await reloadChannels() }
            }
    }
}
