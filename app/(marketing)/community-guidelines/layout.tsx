import type { Metadata } from "next"
import type { ReactNode } from "react"
import { COMMUNITY_GUIDELINES_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = COMMUNITY_GUIDELINES_PAGE_METADATA

export default function CommunityGuidelinesLayout({ children }: { children: ReactNode }) {
  return children
}
