import type { Metadata } from "next"
import type { ReactNode } from "react"
import { ANALYST_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = ANALYST_PAGE_METADATA

export default function AnalystLayout({ children }: { children: ReactNode }) {
  return children
}
