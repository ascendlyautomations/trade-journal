import type { Metadata } from "next"
import type { ReactNode } from "react"
import { STREAKS_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = STREAKS_PAGE_METADATA

export default function StreaksLayout({ children }: { children: ReactNode }) {
  return children
}
