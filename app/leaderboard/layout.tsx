import type { Metadata } from "next"
import type { ReactNode } from "react"
import { LEADERBOARD_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = LEADERBOARD_PAGE_METADATA

export default function LeaderboardLayout({
  children,
}: {
  children: ReactNode
}) {
  return children
}
