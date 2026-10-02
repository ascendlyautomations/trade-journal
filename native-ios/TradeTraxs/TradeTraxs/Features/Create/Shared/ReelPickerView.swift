import SwiftUI

/// Bounded picker of the viewer's **unattached** clips (web: `reels.trade_id IS NULL`).
struct ReelPickerView: View {
    let reels: [Reel]
    let imagePipeline: (any ImagePipeline)?
    let objectStorage: any ObjectStorageProviding
    var isLoading: Bool
    var onSelect: (Reel) -> Void
    var onClose: () -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading clips…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if reels.isEmpty {
                ExperienceEmptyState(
                    icon: .playRectangle,
                    title: "No clips to link",
                    message: "Standalone clips without a trade can be linked here."
                )
            } else {
                List(reels) { reel in
                    Button {
                        onSelect(reel)
                    } label: {
                        TradeClipLinkRowView(
                            reel: reel,
                            imagePipeline: imagePipeline,
                            objectStorage: objectStorage,
                            presentation: .picker
                        )
                    }
                    .accessibilityIdentifier("create.reelPicker.\(reel.id.rawValue)")
                }
                .experienceInsetGroupedListStyle(pageBackground: false)
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Link Clip")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
        .accessibilityIdentifier("create.reelPicker")
    }
}
