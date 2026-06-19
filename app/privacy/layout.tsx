import type { Metadata } from "next"
import type { ReactNode } from "react"
import { PRIVACY_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = PRIVACY_PAGE_METADATA

export default function PrivacyLayout({ children }: { children: ReactNode }) {
  return children
}
