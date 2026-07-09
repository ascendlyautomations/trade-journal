import type { Metadata } from "next"
import type { ReactNode } from "react"
import { BANNED_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = BANNED_PAGE_METADATA

export default function BannedLayout({ children }: { children: ReactNode }) {
  return children
}
