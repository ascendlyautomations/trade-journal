import type { Metadata } from "next"
import type { ReactNode } from "react"
import { TERMS_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = TERMS_PAGE_METADATA
export const revalidate = 86_400

export default function TermsLayout({ children }: { children: ReactNode }) {
  return children
}
