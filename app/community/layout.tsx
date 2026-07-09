import type { Metadata } from "next"
import type { ReactNode } from "react"
import { COMMUNITY_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = COMMUNITY_PAGE_METADATA

export default function CommunityLayout({ children }: { children: ReactNode }) {
  return children
}
