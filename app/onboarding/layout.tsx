import type { Metadata } from "next"
import type { ReactNode } from "react"
import { ONBOARDING_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = ONBOARDING_PAGE_METADATA

/**
 * Full-screen onboarding — standalone app flow (no marketing or app navbar).
 */
export default function OnboardingLayout({ children }: { children: ReactNode }) {
  return (
    <div className="relative min-h-dvh bg-[#020617] text-white">
      <img
        src="/tradetrax-bg.webp"
        alt=""
        aria-hidden
        className="pointer-events-none fixed inset-0 h-full w-full object-cover opacity-[0.22]"
      />
      <div
        className="pointer-events-none fixed inset-0 bg-[#020617]/88"
        aria-hidden
      />
      <div
        className="pointer-events-none fixed inset-0 bg-[radial-gradient(ellipse_90%_55%_at_50%_-5%,rgba(59,130,246,0.18),transparent_50%)]"
        aria-hidden
      />
      <div className="relative z-10 min-h-dvh">{children}</div>
    </div>
  )
}
