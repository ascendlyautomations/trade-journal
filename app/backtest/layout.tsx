import type { Metadata } from "next"
import type { ReactNode } from "react"
import { BACKTEST_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = BACKTEST_PAGE_METADATA

export default function BacktestLayout({ children }: { children: ReactNode }) {
  return children
}
