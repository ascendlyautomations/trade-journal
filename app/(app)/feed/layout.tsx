import type { Metadata } from "next"
import type { ReactNode } from "react"
import ContentModerationRoot from "@/app/components/moderation/ContentModerationRoot"
import { FEED_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = FEED_PAGE_METADATA

export default function FeedLayout({ children }: { children: ReactNode }) {
  return <ContentModerationRoot>{children}</ContentModerationRoot>
}
