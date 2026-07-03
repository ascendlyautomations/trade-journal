import type { PublicUserReview } from "@/lib/userReviewDisplay"
import { demoAvatarUrl } from "@/lib/demo/demoAvatars"
import {
  DEMO_USER_ALEX,
  DEMO_USER_JORDAN,
  DEMO_USER_SARAH,
} from "@/lib/demo/demoFeed"

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
    avatar_snapshot: demoAvatarUrl(DEMO_USER_ALEX),
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
    display_name: "Jordan K.",
    username_snapshot: "jordan_scalps",
    avatar_snapshot: demoAvatarUrl(DEMO_USER_JORDAN),
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
    display_name: "Sarah R.",
    username_snapshot: "sarah_indices",
    avatar_snapshot: demoAvatarUrl(DEMO_USER_SARAH),
  },
]
