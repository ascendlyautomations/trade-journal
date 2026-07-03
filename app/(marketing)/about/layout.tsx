import type { Metadata } from "next"
import type { ReactNode } from "react"
import { ABOUT_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = ABOUT_PAGE_METADATA

export default function AboutLayout({ children }: { children: ReactNode }) {
  return children
}
