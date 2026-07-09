import type { Metadata } from "next"
import type { ReactNode } from "react"
import { REVIEW_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = REVIEW_PAGE_METADATA

export default function ReviewLayout({ children }: { children: ReactNode }) {
  return children
}
