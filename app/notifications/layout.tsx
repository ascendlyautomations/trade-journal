import type { Metadata } from "next"
import type { ReactNode } from "react"
import { NOTIFICATIONS_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = NOTIFICATIONS_PAGE_METADATA

export default function NotificationsLayout({ children }: { children: ReactNode }) {
  return children
}
