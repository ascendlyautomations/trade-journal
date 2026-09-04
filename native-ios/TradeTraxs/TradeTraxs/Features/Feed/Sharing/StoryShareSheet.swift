import SwiftUI
import UIKit

struct StoryShareSheet: View {
    let story: Story
    let ownerUsername: String?
    let data: DataEnvironment
    var onClose: () -> Void

    @State private var viewModel: StoryShareViewModel
    @State private var recipientScope: StoryShareViewModel.RecipientScope?
    @State private var showsExternalShare = false

    @Environment(\.themeColors) private var colors

    init(
        story: Story,
        ownerUsername: String?,
        data: DataEnvironment,
        onClose: @escaping () -> Void
    ) {
        self.story = story
        self.ownerUsername = ownerUsername
        self.data = data
        self.onClose = onClose
        _viewModel = State(
            initialValue: StoryShareViewModel(
                story: story,
                ownerUsername: ownerUsername,
                messagesRepo: data.messages,
                roomsRepo: data.rooms,
                session: data.session
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Send in TradeTraxs") {
                    Button {
                        recipientScope = .messages
                    } label: {
                        Label("Messages", systemImage: "message")
                    }
                    .accessibilityIdentifier("storyShare.messages")

                    Button {
                        recipientScope = .rooms
                    } label: {
                        Label("Trade Rooms", systemImage: "person.3")
                    }
                    .accessibilityIdentifier("storyShare.tradeRooms")
                }

                Section("Share Externally") {
                    Button {
                        showsExternalShare = true
                    } label: {
                        Label("Share Externally", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("storyShare.external")
                }
            }
            .experienceScreenBackground()
            .navigationTitle("Share Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .experienceSheetChrome()
        .sheet(item: $recipientScope) { scope in
            StoryShareRecipientPickerView(
                scope: scope,
                viewModel: viewModel,
                onSelectConversation: { _ in onClose() },
                onSelectRoom: { _ in onClose() },
                onClose: { recipientScope = nil }
            )
        }
        .sheet(isPresented: $showsExternalShare) {
            if let url = DetailContentLink.story(story.id).url {
                StoryExternalShareSheet(items: [viewModel.externalShareText, url])
            }
        }
        .onChange(of: viewModel.phase) { _, phase in
            if phase == .sent, recipientScope != nil {
                recipientScope = nil
                onClose()
            }
        }
    }
}

private struct StoryExternalShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension StoryShareViewModel.RecipientScope: Identifiable {
    var id: String {
        switch self {
        case .messages: return "messages"
        case .rooms: return "rooms"
        }
    }
}

enum StoryShareNavigation {
    @MainActor
    static func open(
        payload: StoryShareMessageSupport.Payload,
        cache: DetailPresentationCache,
        coordinator: NavigationCoordinator?
    ) {
        let storyID = StoryID(payload.storyID)
        if cache.story(id: storyID) == nil {
            cache.seed(StoryShareMessageSupport.provisionalStory(from: payload))
        }
        ExperienceHaptics.play(.selection)
        coordinator?.present(fullScreen: .storyViewer(storyID))
    }
}
