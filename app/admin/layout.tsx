import type { Metadata } from "next"
import type { ReactNode } from "react"
import { ADMIN_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = ADMIN_PAGE_METADATA

export default function AdminLayout({ children }: { children: ReactNode }) {
  return children
}
