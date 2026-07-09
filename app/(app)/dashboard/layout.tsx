import type { Metadata } from "next"
import type { ReactNode } from "react"
import { DASHBOARD_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = DASHBOARD_PAGE_METADATA

export default function DashboardLayout({ children }: { children: ReactNode }) {
  return children
}
