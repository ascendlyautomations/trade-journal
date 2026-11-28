import SwiftUI
import UIKit

struct StoryArchiveView: View {
  let data: DataEnvironment
  let navigationCoordinator: NavigationCoordinator

  @Environment(\.themeColors) private var colors
  @State private var viewModel: StoryArchiveViewModel

  init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
    self.data = data
    self.navigationCoordinator = navigationCoordinator
    _viewModel = State(initialValue: StoryArchiveViewModel(feed: data.feed))
  }

  var body: some View {
    ScrollView {
      if viewModel.isLoading {
        ExperienceIndeterminateProgress()
          .frame(maxWidth: .infinity)
          .experienceScrollEmbeddedSectionFill(minHeight: 360)
          .padding(.top, ExperienceSpacing.xl)
      } else if viewModel.stories.isEmpty {
        Text("Expired stories you have not deleted will appear here.")
          .experienceStyle(.body, color: colors.secondaryText)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .experienceScrollEmbeddedSectionFill(minHeight: 360)
          .padding(ExperienceSpacing.lg)
      } else {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 100), spacing: ExperienceSpacing.sm)],
          spacing: ExperienceSpacing.sm
        ) {
          ForEach(viewModel.stories, id: \.id) { story in
            Button {
              ExperienceHaptics.play(.selection)
              navigationCoordinator.present(fullScreen: .storyViewer(story.id, .storyArchive))
            } label: {
              StoryArchiveThumbnailView(story: story, imagePipeline: data.imagePipeline, storage: data.objectStorage)
            }
            .buttonStyle(.experiencePlain)
          }
        }
        .padding(ExperienceSpacing.md)
      }
    }
    .scrollContentBackground(.hidden)
    .experienceScreenBackground()
    .experienceNavigationTitle(SettingsRoute.storyArchive.title)
    .task { await viewModel.load() }
  }
}

private struct StoryArchiveThumbnailView: View {
  let story: Story
  let imagePipeline: any ImagePipeline
  let storage: any ObjectStorageProviding

  @Environment(\.themeColors) private var colors
  @State private var thumbnail: Image?

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        .fill(colors.fillSecondary.opacity(0.35))
      if let thumbnail {
        thumbnail
          .resizable()
          .scaledToFill()
      }
    }
    .aspectRatio(9 / 16, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    .overlay(alignment: .topTrailing) {
      Text(StoryArchiveAgeBadge.label(createdAt: story.createdAt))
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.55), in: Capsule())
        .padding(6)
    }
    .task(id: story.media.id) {
      await loadThumbnail()
    }
  }

  private func loadThumbnail() async {
    let resolved = await StorySignedMediaResolver.shared.resolvedPlaybackReference(story.media)
    let isVideo = resolved.kind == .video || StoryReplyMessageSupport.isVideoMediaURL(resolved.id)
    if isVideo,
       let image = await VideoPosterFrameLoader.loadPoster(
        thumbnail: nil,
        video: resolved,
        imagePipeline: imagePipeline,
        storage: storage,
        bucket: .stories,
        displayScale: 2,
        allowsVideoFrameExtraction: true
       ) {
      thumbnail = Image(uiImage: image)
      return
    }
    let reference = resolved
    do {
      let data = try await imagePipeline.data(
        for: ImageRequest(reference: reference, purpose: .storyMedia, maxPixelSize: 280)
      )
      if let uiImage = UIImage(data: data) {
        thumbnail = Image(uiImage: uiImage)
      }
    } catch {}
  }
}

private enum StoryArchiveAgeBadge {
  static func label(createdAt: Date, now: Date = Date()) -> String {
    let calendar = Calendar.current
    let from = calendar.startOfDay(for: createdAt)
    let to = calendar.startOfDay(for: now)
    let days = max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    return "\(days)D"
  }
}