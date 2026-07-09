import type { Metadata } from "next"
import type { ReactNode } from "react"
import { AFFILIATE_DASHBOARD_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = AFFILIATE_DASHBOARD_METADATA

export default function AffiliateDashboardLayout({
  children,
}: {
  children: ReactNode
}) {
  return children
}
