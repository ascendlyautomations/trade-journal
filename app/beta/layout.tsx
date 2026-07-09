import type { Metadata } from "next"
import type { ReactNode } from "react"
import { BETA_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = BETA_PAGE_METADATA

export default function BetaLayout({ children }: { children: ReactNode }) {
  return children
}
