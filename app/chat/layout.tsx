import type { Metadata } from "next"
import type { ReactNode } from "react"
import { CHAT_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = CHAT_PAGE_METADATA

export default function ChatLayout({ children }: { children: ReactNode }) {
  return children
}
