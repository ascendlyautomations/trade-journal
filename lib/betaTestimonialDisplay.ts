/** @deprecated Use `@/lib/userReviewDisplay` — legacy re-exports. */
export {
  computeUserReviewStats as computeBetaTestimonialStats,
  formatUserReviewDisplayName,
  formatUserReviewUsername,
  selectFeaturedHomepageReviews as selectHomepageTestimonials,
} from "./userReviewDisplay"
export { SAMPLE_USER_REVIEWS } from "./demo/sampleUserReviews"
export type { PublicUserReview as PublicBetaTestimonial } from "./userReviewDisplay"
