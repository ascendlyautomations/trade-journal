import type { Metadata } from "next"
import type { ReactNode } from "react"
import { DOWNLOAD_PAGE_METADATA } from "@/lib/downloadPageMetadata"

export const metadata: Metadata = DOWNLOAD_PAGE_METADATA

export default function DownloadLayout({ children }: { children: ReactNode }) {
  return children
}