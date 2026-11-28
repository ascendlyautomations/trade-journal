import Foundation

@Observable
@MainActor
final class StoryArchiveViewModel {
  private let feed: any FeedRepository

  var stories: [Story] = []
  var isLoading = false

  init(feed: any FeedRepository) {
    self.feed = feed
  }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      stories = try await feed.archivedStories(limit: 120, offset: 0)
        .sorted { $0.createdAt > $1.createdAt }
    } catch {
      stories = []
    }
  }
}