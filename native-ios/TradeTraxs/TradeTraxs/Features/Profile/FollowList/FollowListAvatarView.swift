import SwiftUI
import UIKit

/// Compact avatar for follow lists — reuses the shared image pipeline / memory cache.
struct FollowListAvatarView: View {
    let profile: Profile
    let imagePipeline: any ImagePipeline
    var size: CGFloat = 48

    @State private var image: Image?

    var body: some View {
        ExperienceAvatar(
            initials: ProfileDisplay.initials(
                displayName: profile.displayName,
                username: profile.username
            ),
            image: image,
            size: size
        )
        .task(id: profile.avatar?.id) {
            await load()
        }
    }

    private func load() async {
        guard let reference = profile.avatar else {
            image = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 128
                )
            )
            if let ui = UIImage(data: data) {
                image = Image(uiImage: ui)
            }
        } catch {
            image = nil
        }
    }
}
