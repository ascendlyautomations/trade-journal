import type { Metadata } from "next"
import type { ReactNode } from "react"
import { ONBOARDING_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = ONBOARDING_PAGE_METADATA

/**
 * Full-screen onboarding — standalone app flow (no marketing or app navbar).
 */
export default function OnboardingLayout({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46]">
      {children}
    </div>
  )
}
