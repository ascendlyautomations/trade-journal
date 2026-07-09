import type { Metadata } from "next"
import type { ReactNode } from "react"
import { SEARCH_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = SEARCH_PAGE_METADATA

export default function SearchLayout({ children }: { children: ReactNode }) {
  return children
}
