import Foundation

/// Which Supabase table backs a post detail screen.
nonisolated enum PostDetailLoadSource: Hashable, Sendable {
    /// `public.posts` — feed posts and feed trade cards.
    case feedPost
    /// `public.profile_posts` — profile wall posts.
    case profilePost
}
