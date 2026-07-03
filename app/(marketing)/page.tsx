import type { Metadata } from "next"
import { Suspense } from "react"
import LandingPageClient from "@/app/components/LandingPageClient"
import {
  SkeletonFeaturedTradesSection,
  SkeletonTestimonialsSection,
} from "@/app/components/ui/skeletons"
import LandingFeaturedTradesSectionLoader from "@/app/components/landing/LandingFeaturedTradesSectionLoader"
import LandingTestimonialsSectionLoader from "@/app/components/landing/LandingTestimonialsSectionLoader"
import {
  DEFAULT_OG_IMAGE_PATH,
  DEFAULT_SITE_DESCRIPTION,
  HOME_PAGE_TITLE,
  SITE_NAME,
  SITE_URL,
} from "@/lib/site"

export const metadata: Metadata = {
  title: {
    absolute: HOME_PAGE_TITLE,
  },
  description: DEFAULT_SITE_DESCRIPTION,
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    url: SITE_URL,
    title: HOME_PAGE_TITLE,
    description: DEFAULT_SITE_DESCRIPTION,
    siteName: SITE_NAME,
    images: [
      {
        url: DEFAULT_OG_IMAGE_PATH,
        alt: SITE_NAME,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: HOME_PAGE_TITLE,
    description: DEFAULT_SITE_DESCRIPTION,
    images: [DEFAULT_OG_IMAGE_PATH],
  },
}

/** Static shell (hero, features, FAQ) — daily ISR; reviews/trades stream from Suspense loaders. */
export const revalidate = 86_400

export default function HomePage() {
  return (
    <LandingPageClient
      featuredTradesSection={
        <Suspense fallback={<SkeletonFeaturedTradesSection />}>
          <LandingFeaturedTradesSectionLoader />
        </Suspense>
      }
      testimonialsSection={
        <Suspense fallback={<SkeletonTestimonialsSection />}>
          <LandingTestimonialsSectionLoader />
        </Suspense>
      }
    />
  )
}
