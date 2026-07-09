import type { Metadata } from "next"
import type { ReactNode } from "react"
import { SUPPORT_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = SUPPORT_PAGE_METADATA

export default function SupportLayout({ children }: { children: ReactNode }) {
  return children
}
