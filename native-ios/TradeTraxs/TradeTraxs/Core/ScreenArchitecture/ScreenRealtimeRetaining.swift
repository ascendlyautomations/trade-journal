import Foundation

/// Realtime lifecycle for domains shared by multiple screens (Messages + Trade Rooms).
///
/// Prefer retain/release over bare subscribe/unsubscribe so overlapping homes do not
/// tear down watchers while another surface is still visible.
@MainActor
protocol ScreenRealtimeRetaining: AnyObject {
    func retainRealtime() async
    func releaseRealtime()
}
