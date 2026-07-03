import type { Metadata } from "next"
import type { ReactNode } from "react"
import { PRICING_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = PRICING_PAGE_METADATA

export default function PricingLayout({ children }: { children: ReactNode }) {
  return children
}
