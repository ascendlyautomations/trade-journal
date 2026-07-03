import type { Metadata } from "next"
import type { ReactNode } from "react"
import { LEGAL_HUB_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = LEGAL_HUB_PAGE_METADATA

export default function LegalHubLayout({ children }: { children: ReactNode }) {
  return children
}
