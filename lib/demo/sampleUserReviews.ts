import type { PublicUserReview } from "@/lib/userReviewDisplay"

export const SAMPLE_USER_REVIEWS: PublicUserReview[] = [
  {
    id: "sample-1",
    rating: 5,
    title: "Finally, a journal that keeps up",
    review:
      "TradeTraxs makes it easy to log trades, review performance, and stay accountable. The analytics and community features feel built for serious traders.",
    would_recommend: true,
    featured: true,
    created_at: "2026-06-01T12:00:00.000Z",
    display_name: "Alex M.",
    username_snapshot: "alex_futures",
    avatar_snapshot: "/homepage/testimonials/beta-user-01.webp",
  },
  {
    id: "sample-2",
    rating: 5,
    title: "Clean, focused, and social",
    review:
      "I love being able to journal privately while still sharing selected trades with the community. It strikes the right balance between tracking and connecting.",
    would_recommend: true,
    featured: true,
    created_at: "2026-06-08T12:00:00.000Z",
    display_name: "George K.",
    username_snapshot: "george_scalps",
    avatar_snapshot: "/homepage/testimonials/beta-user-02.webp",
  },
  {
    id: "sample-3",
    rating: 5,
    title: "Built for improvement",
    review:
      "The dashboard and weekly stats help me spot patterns I was missing in my old spreadsheet workflow. Beta feedback is clearly shaping the product.",
    would_recommend: true,
    featured: true,
    created_at: "2026-06-15T12:00:00.000Z",
    display_name: "Timmy R.",
    username_snapshot: "timmy_trades",
    avatar_snapshot: "/homepage/testimonials/beta-user-03.webp",
  },
]
