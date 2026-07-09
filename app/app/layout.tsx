import type { Metadata } from "next"
import type { ReactNode } from "react"
import { INPUT_TRADE_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = INPUT_TRADE_PAGE_METADATA

export default function InputTradeLayout({ children }: { children: ReactNode }) {
  return children
}
