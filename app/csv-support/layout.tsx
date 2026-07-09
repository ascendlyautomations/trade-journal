import type { Metadata } from "next"
import type { ReactNode } from "react"
import { CSV_SUPPORT_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = CSV_SUPPORT_PAGE_METADATA

export default function CsvSupportLayout({ children }: { children: ReactNode }) {
  return children
}
