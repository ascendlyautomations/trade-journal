import type { Metadata } from "next"
import type { ReactNode } from "react"
import { REFERRALS_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = REFERRALS_PAGE_METADATA

export default function ReferralsLayout({ children }: { children: ReactNode }) {
  return children
}
