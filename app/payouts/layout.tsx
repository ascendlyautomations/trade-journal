import type { Metadata } from "next"
import type { ReactNode } from "react"
import { PAYOUTS_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = PAYOUTS_PAGE_METADATA

export default function PayoutsLayout({ children }: { children: ReactNode }) {
  return children
}
