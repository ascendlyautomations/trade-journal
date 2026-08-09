import Foundation
import SwiftUI
import UIKit

/// Shared author display helpers for content detail ViewModels.
@MainActor
enum DetailAuthorPresentation {
    static func displayName(for author: Profile?) -> String {
        guard let author else { return "Trader" }
        return author.displayName.isEmpty ? author.username : author.displayName
    }

    static func username(for author: Profile?) -> String {
        author.map { "@\($0.username)" } ?? ""
    }

    static func initials(for author: Profile?) -> String {
        ProfileDisplay.initials(
            displayName: author?.displayName ?? "",
            username: author?.username ?? ""
        )
    }

    static func loadAvatar(
        for author: Profile?,
        imagePipeline: any ImagePipeline
    ) async -> Image? {
        guard let reference = author?.avatar else { return nil }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 128
                )
            )
            let decoded = await Task.detached(priority: .utility) {
                UIImage(data: data)
            }.value
            return decoded.map { Image(uiImage: $0) }
        } catch {
            return nil
        }
    }
}
