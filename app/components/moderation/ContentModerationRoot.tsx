"use client"

import type { ReactNode } from "react"
import ContentModerationProvider from "@/app/components/moderation/ContentModerationProvider"

export default function ContentModerationRoot({
  children,
}: {
  children: ReactNode
}) {
  return <ContentModerationProvider>{children}</ContentModerationProvider>
}
