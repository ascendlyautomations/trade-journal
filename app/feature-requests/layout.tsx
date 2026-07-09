import type { Metadata } from "next"
import type { ReactNode } from "react"
import { FEATURE_REQUESTS_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = FEATURE_REQUESTS_PAGE_METADATA

export default function FeatureRequestsLayout({
  children,
}: {
  children: ReactNode
}) {
  return children
}
