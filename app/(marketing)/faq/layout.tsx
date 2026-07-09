import type { Metadata } from "next"
import type { ReactNode } from "react"
import JsonLd from "@/app/components/JsonLd"
import { FAQ_PAGE_METADATA } from "@/lib/publicRouteMetadata"
import { breadcrumbJsonLd, faqPageJsonLd } from "@/lib/structuredData"

export const metadata: Metadata = FAQ_PAGE_METADATA

export default function FaqLayout({ children }: { children: ReactNode }) {
  return (
    <>
      <JsonLd
        data={[
          faqPageJsonLd(),
          breadcrumbJsonLd([
            { name: "Home", path: "/" },
            { name: "FAQ", path: "/faq" },
          ]),
        ]}
      />
      {children}
    </>
  )
}
