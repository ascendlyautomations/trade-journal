import type { Metadata } from "next"
import type { ReactNode } from "react"
import { ACHIEVEMENTS_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = ACHIEVEMENTS_PAGE_METADATA

export default function AchievementsLayout({ children }: { children: ReactNode }) {
  return children
}
