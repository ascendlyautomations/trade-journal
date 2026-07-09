import type { Metadata } from "next"
import type { ReactNode } from "react"
import { IMPORT_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = IMPORT_PAGE_METADATA

export default function ImportLayout({ children }: { children: ReactNode }) {
  return children
}
