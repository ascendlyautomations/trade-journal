import type { Metadata } from "next"
import type { ReactNode } from "react"
import { EXPLORE_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = EXPLORE_PAGE_METADATA

export default function ExploreLayout({ children }: { children: ReactNode }) {
  return children
}
