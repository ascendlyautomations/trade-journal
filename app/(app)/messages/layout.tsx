import type { Metadata } from "next"
import type { ReactNode } from "react"
import { MESSAGES_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = MESSAGES_PAGE_METADATA

export default function MessagesLayout({ children }: { children: ReactNode }) {
  return children
}
