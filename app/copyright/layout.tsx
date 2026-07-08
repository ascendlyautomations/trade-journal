import type { Metadata } from "next"
import type { ReactNode } from "react"
import { COPYRIGHT_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = COPYRIGHT_PAGE_METADATA
export const revalidate = 86_400

export default function CopyrightLayout({ children }: { children: ReactNode }) {
  return children
}
