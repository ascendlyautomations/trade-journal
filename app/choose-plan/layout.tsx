import type { Metadata } from "next"
import type { ReactNode } from "react"
import { CHOOSE_PLAN_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = CHOOSE_PLAN_PAGE_METADATA

/**
 * Post-auth plan selection for Google signups — standalone flow (no app navbar).
 */
export default function ChoosePlanLayout({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46]">
      {children}
    </div>
  )
}
