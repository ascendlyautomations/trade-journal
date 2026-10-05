import SwiftUI

/// Create hub — Trade / Post / Clip / Achievement / Story / Payout.
struct ComposeChooserView: View {
    let onAddTrade: () -> Void
    let onCreatePost: () -> Void
    let onCreateReel: () -> Void
    let onCreateAchievement: () -> Void
    let onCreateStory: () -> Void
    let onRecordWithdrawal: () -> Void
    let onClose: () -> Void
    var draftsRepository: (any ContentDraftRepository)? = nil
    var onOpenDraft: (ContentDraft) -> Void = { _ in }

    @Environment(\.themeColors) private var colors
    @State private var showsDrafts = false

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
                .listRowInsets(composeRowInsets)
                .accessibilityIdentifier("compose.addTrade")

                Button(action: onCreatePost) {
                    SettingsNavigationRow(
                        title: "Post",
                        subtitle: "Share with the community",
                        systemImage: "text.bubble"
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(composeRowInsets)
                .accessibilityIdentifier("compose.post")

                Button(action: onCreateReel) {
                    SettingsNavigationRow(
                        title: "Clip",
                        subtitle: "Share a short trading video",
                        systemImage: "play.rectangle.fill"
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(composeRowInsets)
                .accessibilityIdentifier("compose.reel")

                Button(action: onCreateAchievement) {
                    SettingsNavigationRow(
                        title: "Achievement",
                        subtitle: "Share a milestone",
                        systemImage: "trophy"
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(composeRowInsets)
                .accessibilityIdentifier("compose.achievement")

                Button(action: onCreateStory) {
                    SettingsNavigationRow(
                        title: "Story",
                        subtitle: "Share a photo for 24 hours",
                        systemImage: "camera.circle.fill"
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(composeRowInsets)
                .accessibilityIdentifier("compose.story")

                Button(action: onRecordWithdrawal) {
                    SettingsNavigationRow(
                        title: "Withdrawal",
                        subtitle: "Record money withdrawn from a Live account",
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(composeRowInsets)
                .accessibilityIdentifier("compose.withdrawal")
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .listSectionSpacing(ExperienceSpacing.xs)
        .contentMargins(.top, ExperienceSpacing.xxs, for: .scrollContent)
        .experienceNavigationTitle("Create")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
            if showsDraftsAction {
                ToolbarItem(placement: .primaryAction) {
                    Button("Drafts") { showsDrafts = true }
                        .font(.subheadline.weight(.regular))
                        .accessibilityIdentifier("compose.drafts")
                }
            }
        }
        .navigationDestination(isPresented: $showsDrafts) {
            if let draftsRepository {
                ContentDraftsListView(repository: draftsRepository, onOpen: onOpenDraft)
            }
        }
        .toolbarBackground(colors.groupedBackground, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .accessibilityIdentifier("compose.chooser")
    }

    private var showsDraftsAction: Bool {
        draftsRepository != nil && ExploreModeSupport.canWriteContent
    }

    private var composeRowInsets: EdgeInsets {
        EdgeInsets(
            top: ExperienceSpacing.xxs,
            leading: ExperienceSpacing.md,
            bottom: ExperienceSpacing.xxs,
            trailing: ExperienceSpacing.md
        )
    }
}
