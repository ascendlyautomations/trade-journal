import type { Metadata } from "next"
import type { ReactNode } from "react"
import { TERMS_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = TERMS_PAGE_METADATA

export default function TermsLayout({ children }: { children: ReactNode }) {
  return children
}
