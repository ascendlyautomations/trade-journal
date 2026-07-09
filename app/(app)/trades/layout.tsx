import type { Metadata } from "next"
import type { ReactNode } from "react"
import { TRADES_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = TRADES_PAGE_METADATA

export default function TradesLayout({ children }: { children: ReactNode }) {
  return children
}
