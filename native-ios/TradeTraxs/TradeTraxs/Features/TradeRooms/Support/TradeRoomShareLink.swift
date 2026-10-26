import Foundation
import SwiftUI
import UIKit

/// Canonical Trade Room invite URLs — matches ``lib/tradeRoomShareUrl.ts`` and Universal Links.
enum TradeRoomShareLink {
    static let productionHost = "https://www.tradetraxs.com"

    static func roomKey(slug: String?, roomID: RoomID) -> String {
        let trimmed = slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? roomID.rawValue : trimmed
    }

    static func universalURL(
        slug: String?,
        roomID: RoomID,
        sectionID: String? = nil,
        messageID: String? = nil
    ) -> URL? {
        let key = roomKey(slug: slug, roomID: roomID)
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        var components = URLComponents(string: "\(productionHost)/room/\(encoded)")
        var items: [URLQueryItem] = []
        if let sectionID, !sectionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "section", value: sectionID))
        }
        if let messageID, !messageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "message", value: messageID))
        }
        if !items.isEmpty {
            components?.queryItems = items
        }
        return components?.url
    }

    static func inviteString(slug: String?, roomID: RoomID) -> String {
        universalURL(slug: slug, roomID: roomID)?.absoluteString
            ?? "\(productionHost)/room/\(roomID.rawValue)"
    }
}

struct TradeRoomInviteActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
