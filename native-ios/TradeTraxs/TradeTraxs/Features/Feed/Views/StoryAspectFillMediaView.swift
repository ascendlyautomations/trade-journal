import SwiftUI
import UIKit

/// Full-screen aspect-fill media for 9:16 rendered story images.
struct StoryAspectFillMediaView: View {
    let reference: MediaReference?
    let imagePipeline: any ImagePipeline
    var accessibilityIdentifier: String = "feed.story.media"
    var onLoadFailed: (() -> Void)?

    @Environment(\.displayScale) private var displayScale
    @State private var displayImage: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if didFail || reference == nil {
                Color.black
            } else {
                ExperienceIndeterminateProgress()
                    .tint(.white)
            }
        }
        .task(id: "\(reference?.id ?? "")|\(displayScale)") {
            await loadDisplayImage()
        }
        .onChange(of: didFail) { _, failed in
            guard failed else { return }
            onLoadFailed?()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isImage)
    }

    private func loadDisplayImage() async {
        guard let reference else {
            displayImage = nil
            didFail = true
            return
        }
        didFail = false
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .storyMedia,
                    maxPixelSize: nil,
                    allowsProgressiveLoading: true
                )
            )
            let scale = displayScale
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data, scale: scale)
            }.value
            guard let decoded else {
                didFail = true
                displayImage = nil
                StoryDebug.log("viewer.image.decodeFailed", "ref=\(String(reference.id.prefix(80)))")
                return
            }
            displayImage = decoded
            StoryDebug.log("viewer.image.ok", "ref=\(String(reference.id.prefix(80))) bytes=\(data.count)")
        } catch {
            didFail = true
            displayImage = nil
            StoryDebug.log(
                "viewer.image.error",
                "ref=\(String(reference.id.prefix(80))) error=\(error.localizedDescription)"
            )
        }
    }
}
