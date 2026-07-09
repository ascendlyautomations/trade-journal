import type { Metadata } from "next"
import type { ReactNode } from "react"
import JsonLd from "@/app/components/JsonLd"
import { PRICING_PAGE_METADATA } from "@/lib/publicRouteMetadata"
import { breadcrumbJsonLd } from "@/lib/structuredData"

export const metadata: Metadata = PRICING_PAGE_METADATA

export default function PricingLayout({ children }: { children: ReactNode }) {
  return (
    <>
      <JsonLd
        data={breadcrumbJsonLd([
          { name: "Home", path: "/" },
          { name: "Pricing", path: "/pricing" },
        ])}
      />
      {children}
    </>
  )
}
