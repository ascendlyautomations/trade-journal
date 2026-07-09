import type { Metadata } from "next"
import type { ReactNode } from "react"
import { CALENDAR_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = CALENDAR_PAGE_METADATA

export default function CalendarLayout({ children }: { children: ReactNode }) {
  return children
}
