import type { Metadata } from "next"
import type { ReactNode } from "react"
import { FEEDBACK_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = FEEDBACK_PAGE_METADATA

export default function FeedbackLayout({ children }: { children: ReactNode }) {
  return children
}
