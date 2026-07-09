import type { Metadata } from "next"
import type { ReactNode } from "react"
import { PROPFIRM_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = PROPFIRM_PAGE_METADATA

export default function PropFirmLayout({ children }: { children: ReactNode }) {
  return children
}
