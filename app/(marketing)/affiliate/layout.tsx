import type { Metadata } from "next"
import type { ReactNode } from "react"
import { AFFILIATE_PROGRAM_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = AFFILIATE_PROGRAM_PAGE_METADATA

export default function AffiliateProgramLayout({ children }: { children: ReactNode }) {
  return children
}
