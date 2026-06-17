import type { Metadata } from "next"
import type { ReactNode } from "react"
import { FAQ_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = FAQ_PAGE_METADATA

export default function FaqLayout({ children }: { children: ReactNode }) {
  return children
}
