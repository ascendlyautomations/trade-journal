import type { Metadata } from "next"
import type { ReactNode } from "react"
import { CREATOR_GUIDELINES_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = CREATOR_GUIDELINES_PAGE_METADATA

export default function CreatorGuidelinesLayout({ children }: { children: ReactNode }) {
  return children
}
