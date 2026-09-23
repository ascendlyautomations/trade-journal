import Foundation

#if DEBUG
enum ActivityRealtimeDebugLog {
    static func notificationInsert(id: String, hydrated: Bool) {
        print("[ActivityRealtime] notificationInsert id=\(id) hydrated=\(hydrated)")
    }

    static func notificationUpdate(id: String, hydrated: Bool) {
        print("[ActivityRealtime] notificationUpdate id=\(id) hydrated=\(hydrated)")
    }

    static func notificationDelete(id: String) {
        print("[ActivityRealtime] notificationDelete id=\(id)")
    }

    static func notificationHydration(id: String, reason: String) {
        print("[ActivityRealtime] notificationHydration id=\(id) reason=\(reason)")
    }

    static func duplicateDeliveryIgnored(id: String) {
        print("[ActivityRealtime] duplicateDeliveryIgnored id=\(id)")
    }

    static func networkFallback(reason: String) {
        print("[ActivityRealtime] networkFallback reason=\(reason)")
    }
}
#endif
