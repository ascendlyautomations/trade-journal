import SwiftUI

/// Create hub — Trade / Post / Clip / Achievement / Story.
struct ComposeChooserView: View {
    let onAddTrade: () -> Void
    let onCreatePost: () -> Void
    let onCreateReel: () -> Void
    let onCreateAchievement: () -> Void
    let onCreateStory: () -> Void
    let onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                Button(action: onAddTrade) {
                    SettingsNavigationRow(
                        title: "Add Trade",
                        subtitle: "Log a completed trade",
                        systemImage: "plus.circle.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("compose.addTrade")

                Button(action: onCreatePost) {
                    SettingsNavigationRow(
                        title: "Post",
                        subtitle: "Share with the community",
                        systemImage: "text.bubble"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("compose.post")

                Button(action: onCreateReel) {
                    SettingsNavigationRow(
                        title: "Clip",
                        subtitle: "Share a short trading video",
                        systemImage: "play.rectangle.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("compose.reel")

                Button(action: onCreateAchievement) {
                    SettingsNavigationRow(
                        title: "Achievement",
                        subtitle: "Share a milestone",
                        systemImage: "trophy"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("compose.achievement")

                Button(action: onCreateStory) {
                    SettingsNavigationRow(
                        title: "Story",
                        subtitle: "Share a photo for 24 hours",
                        systemImage: "camera.circle.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("compose.story")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Create")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
        .accessibilityIdentifier("compose.chooser")
    }
}
