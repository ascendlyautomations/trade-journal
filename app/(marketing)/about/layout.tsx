import type { Metadata } from "next"
import type { ReactNode } from "react"
import JsonLd from "@/app/components/JsonLd"
import { ABOUT_PAGE_METADATA } from "@/lib/publicRouteMetadata"
import { breadcrumbJsonLd } from "@/lib/structuredData"

export const metadata: Metadata = ABOUT_PAGE_METADATA

export default function AboutLayout({ children }: { children: ReactNode }) {
  return (
    <>
      <JsonLd
        data={breadcrumbJsonLd([
          { name: "Home", path: "/" },
          { name: "About", path: "/about" },
        ])}
      />
      {children}
    </>
  )
}
