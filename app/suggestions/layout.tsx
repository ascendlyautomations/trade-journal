import type { Metadata } from "next"
import type { ReactNode } from "react"
import { SUGGESTIONS_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = SUGGESTIONS_PAGE_METADATA

export default function SuggestionsLayout({ children }: { children: ReactNode }) {
  return children
}
