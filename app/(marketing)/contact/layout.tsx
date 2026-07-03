import type { Metadata } from "next"
import type { ReactNode } from "react"
import { CONTACT_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = CONTACT_PAGE_METADATA

export default function ContactLayout({ children }: { children: ReactNode }) {
  return children
}
