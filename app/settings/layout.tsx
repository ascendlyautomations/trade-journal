import type { Metadata } from "next"
import type { ReactNode } from "react"
import { SETTINGS_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = SETTINGS_PAGE_METADATA

export default function SettingsLayout({ children }: { children: ReactNode }) {
  return children
}
