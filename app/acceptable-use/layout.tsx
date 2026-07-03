import type { Metadata } from "next"
import type { ReactNode } from "react"
import { ACCEPTABLE_USE_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = ACCEPTABLE_USE_PAGE_METADATA

export default function AcceptableUseLayout({ children }: { children: ReactNode }) {
  return children
}
