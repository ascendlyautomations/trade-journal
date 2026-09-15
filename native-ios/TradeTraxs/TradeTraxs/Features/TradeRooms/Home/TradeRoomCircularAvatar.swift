import SwiftUI
import UIKit

/// Circular Trade Room image — shared lists, discovery rows, and navigation chrome.
struct TradeRoomCircularAvatar: View {
    let imageReference: MediaReference?
    let imagePipeline: any ImagePipeline
    var diameter: CGFloat = 32

    @Environment(\.themeColors) private var colors
    @State private var logoImage: Image?

    var body: some View {
        Group {
            if let logoImage {
                logoImage
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    colors.fillSecondary
                    ExperienceIcon(icon: .rooms, size: .sm, color: colors.accent)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(colors.border.opacity(0.35), lineWidth: 0.5)
        )
        .task(id: imageReference?.id) {
            await loadLogo()
        }
        .accessibilityHidden(true)
    }

    private func loadLogo() async {
        guard let reference = imageReference else {
            logoImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: max(96, Int(diameter * 3))
                )
            )
            if let ui = UIImage(data: data) {
                logoImage = Image(uiImage: ui)
            }
        } catch {
            logoImage = nil
        }
    }
}
