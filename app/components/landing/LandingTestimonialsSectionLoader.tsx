import { getCachedLandingReviews } from "@/lib/landingServerData"
import LandingTestimonialsSection from "./LandingTestimonialsSection"

/** Server loader — cached reviews revalidate on 30-minute schedule. */
export default async function LandingTestimonialsSectionLoader() {
  const reviews = await getCachedLandingReviews()
  return <LandingTestimonialsSection reviews={reviews} />
}
