import type { Metadata } from "next"
import type { ReactNode } from "react"
import { HELP_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = HELP_PAGE_METADATA

export default function HelpLayout({ children }: { children: ReactNode }) {
  return children
}
