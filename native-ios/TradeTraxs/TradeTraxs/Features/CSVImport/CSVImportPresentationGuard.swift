import Foundation

/// Prevents incidental `fullScreenCover` dismissal while CSV import is mid-flight.
@MainActor
enum CSVImportPresentationGuard {
    private(set) static var isActive = false

    static func enterFlow() {
        isActive = true
        #if DEBUG
        print("[CSV_IMPORT] flowGuard=active")
        #endif
    }

    static func leaveFlow() {
        isActive = false
        #if DEBUG
        print("[CSV_IMPORT] flowGuard=inactive")
        #endif
    }
}
