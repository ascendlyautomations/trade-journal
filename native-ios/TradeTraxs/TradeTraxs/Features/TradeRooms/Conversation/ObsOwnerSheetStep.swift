import Foundation

enum ObsOwnerSheetStep: Identifiable, Equatable {
    case methodSelection
    case manage(roomID: RoomID)

    var id: String {
        switch self {
        case .methodSelection:
            "methodSelection"
        case .manage(let roomID):
            "manage-\(roomID.rawValue)"
        }
    }
}
