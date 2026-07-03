import { SafeProfileAvatar } from "@/app/components/SafeProfileAvatar"
import StarRatingDisplay from "@/app/components/beta/StarRatingDisplay"
import {
  computeUserReviewStats,
  formatUserReviewDisplayName,
  formatUserReviewUsername,
  resolvePublicReviewAvatar,
  selectFeaturedHomepageReviews,
  type PublicUserReview,
} from "@/lib/userReviewDisplay"
import { SAMPLE_USER_REVIEWS } from "@/lib/demo/sampleUserReviews"
import {
  LANDING_CARD_FULL,
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_LEAD_GAP,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_CONTENT_GAP,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
} from "@/lib/landingPageUi"

function formatReviewDate(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString(undefined, {
      month: "short",
      year: "numeric",
    })
  } catch {
    return ""
  }
}

function TestimonialCard({ testimonial }: { testimonial: PublicUserReview }) {
  const displayName = formatUserReviewDisplayName(testimonial)
  const username = formatUserReviewUsername(testimonial)
  const dateLabel = formatReviewDate(testimonial.created_at)
  const avatarSrc = resolvePublicReviewAvatar(testimonial)

  return (
    <article className={`${LANDING_CARD_FULL} flex min-h-[220px] flex-col p-5 md:min-h-[280px] md:p-8`}>
      <div className="flex items-start justify-between gap-2 md:gap-3">
        <StarRatingDisplay rating={testimonial.rating} className="text-sm md:text-lg" />
        <span className="shrink-0 rounded-full border border-amber-400/30 bg-amber-500/15 px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide text-amber-200">
          Verified Beta Tester
        </span>
      </div>

      {testimonial.title?.trim() ? (
        <h3 className="mt-3 text-base font-semibold text-white md:mt-4 md:text-lg">
          {testimonial.title}
        </h3>
      ) : null}
      <p
        className={`${testimonial.title?.trim() ? "mt-2" : "mt-3 md:mt-4"} flex-1 text-sm leading-relaxed text-gray-300 md:text-base`}
      >
        &ldquo;{testimonial.review}&rdquo;
      </p>

      <footer className="mt-4 flex items-center gap-3 border-t border-white/10 pt-3 md:mt-6 md:pt-4">
        <SafeProfileAvatar
          src={avatarSrc}
          alt={displayName}
          className="h-10 w-10 shrink-0 rounded-full"
        />
        <div className="min-w-0">
          <p className="truncate font-medium text-white">{displayName}</p>
          <p className="mt-0.5 truncate text-sm text-gray-500">
            {[username, dateLabel].filter(Boolean).join(" · ")}
          </p>
        </div>
      </footer>
    </article>
  )
}

type LandingTestimonialsSectionProps = {
  reviews: PublicUserReview[]
}

export default function LandingTestimonialsSection({
  reviews,
}: LandingTestimonialsSectionProps) {
  const stats = computeUserReviewStats(reviews)
  const featuredLive = selectFeaturedHomepageReviews(reviews, 3)
  const displayCards =
    featuredLive.length > 0 ? featuredLive : SAMPLE_USER_REVIEWS.slice(0, 3)

  return (
    <section
      id="testimonials"
      className={`relative z-10 ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="testimonials-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div className="mx-auto max-w-3xl text-center">
          <h2 id="testimonials-heading" className={LANDING_HEADLINE_SM}>
            Real Stories From The Community
          </h2>
          <p className={`${LANDING_LEAD} mx-auto ${LANDING_LEAD_GAP}`}>
            Traders are making TradeTraxs home.
          </p>

          {stats.count > 0 ? (
            <div className="mt-5 flex flex-col items-center gap-1.5 md:mt-8 md:gap-2">
              <div className="flex flex-wrap items-center justify-center gap-2 md:gap-3">
                <StarRatingDisplay
                  rating={Math.round(stats.averageRating)}
                  className="text-lg md:text-xl"
                />
                <span className="text-base font-semibold text-white tabular-nums md:text-lg">
                  {stats.averageRating.toFixed(1)}/5
                </span>
              </div>
              <p className="text-sm text-gray-500">
                Based on {stats.count} approved review{stats.count === 1 ? "" : "s"}
              </p>
            </div>
          ) : (
            <p className="mt-4 text-sm text-gray-500 md:mt-6">
              Community reviews will appear here as they are approved.
            </p>
          )}
        </div>

        <div className={`${LANDING_SECTION_CONTENT_GAP} grid gap-4 md:grid-cols-3 md:gap-5`}>
          {displayCards.map((testimonial) => (
            <TestimonialCard key={testimonial.id} testimonial={testimonial} />
          ))}
        </div>
      </div>
    </section>
  )
}
